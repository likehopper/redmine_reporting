# frozen_string_literal: true
# File: redmine_reporting/test/unit/credit_contract_test.rb
#
# Redmine Reporting - project reporting plugin
# SPDX-License-Identifier: GPL-2.0-or-later
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

require_relative "../test_helper"

class CreditContractTest < ActiveSupport::TestCase
  include ReportingTestData

  # Redmine fixtures: trackers 1 Bug, 2 Feature request, 3 Support request;
  # activities 9 Design, 10 Development, 11 QA.
  BUG, FEATURE, SUPPORT = 1, 2, 3
  DESIGN, DEVELOPMENT, QA = 9, 10, 11

  def setup
    trackers = Tracker.where(id: [BUG, FEATURE, SUPPORT]).to_a
    [@project, @child].each { |project| project.update!(trackers: trackers) }
    @grandchild = create_project("reporting-query-grandchild", parent: @child, trackers: trackers).reload
    @project.reload
    @child.reload
  end

  def test_dates_trackers_and_envelopes_are_required
    contract = ReportingCreditContract.new(project: @project, name: "TMA", starts_on: Date.new(2027, 1, 31), ends_on: Date.new(2027, 1, 1))
    refute contract.valid?
    assert contract.errors.key?(:ends_on)
    assert contract.errors.key?(:tracker_ids)
    assert_includes contract.errors[:base], I18n.t("activerecord.errors.messages.reporting_envelope_required")
  end

  def test_a_tracker_belongs_to_one_contract_of_the_project_at_a_time
    contract(trackers: [BUG, FEATURE], from: Date.new(2027, 1, 1), to: Date.new(2027, 12, 31))
    clash = build_contract(trackers: [FEATURE], from: Date.new(2027, 6, 1), to: Date.new(2028, 5, 31))
    refute clash.valid?
    assert_match "TMA", clash.errors[:base].join
    # Other trackers, or the day after, are fine.
    assert build_contract(trackers: [SUPPORT], from: Date.new(2027, 6, 1), to: Date.new(2028, 5, 31)).valid?
    assert build_contract(trackers: [FEATURE], from: Date.new(2028, 1, 1), to: Date.new(2028, 3, 31)).valid?
    # A subproject's own contract may cover the same tracker.
    assert build_contract(project: @child, trackers: [FEATURE], from: Date.new(2027, 6, 1), to: Date.new(2027, 8, 31)).valid?
  end

  def test_envelopes_must_not_share_time
    shared = build_contract(envelopes: [{name: "Dev", days: 5, activity_ids: [DEVELOPMENT, QA]},
                                        {name: "QA", days: 5, activity_ids: [QA], issue_privacy: "private"}])
    refute shared.valid?
    assert_match "Dev", shared.errors[:base].join
    # The same activity on public and private issues is two different shares.
    assert build_contract(envelopes: [{name: "Dev", days: 5, activity_ids: [DEVELOPMENT], issue_privacy: "public"},
                                      {name: "Flat rate", days: 2, activity_ids: [DEVELOPMENT], issue_privacy: "private"},
                                      {name: "Other", days: 1, other_activities: true}]).valid?
    refute build_contract(envelopes: [{name: "Other", days: 1, other_activities: true},
                                      {name: "Other private", days: 1, other_activities: true, issue_privacy: "private"}]).valid?
    listed = build_contract(envelopes: [{name: "Dev", days: 5}])
    refute listed.valid?
  end

  def test_movements_are_dated_within_the_contract_and_not_zero
    contract = contract()
    envelope = contract.envelopes.first
    refute envelope.movements.build(date: Date.new(2028, 1, 1), days: 2).valid?
    refute envelope.movements.build(date: Date.new(2027, 3, 1), days: 0).valid?
    assert envelope.movements.build(date: Date.new(2027, 3, 1), days: -2, comment: "Debt").valid?
  end

  def test_renewal_keeps_whole_months_or_else_the_number_of_days
    assert_equal Date.new(2028, 1, 14), build_contract(from: Date.new(2026, 1, 15), to: Date.new(2027, 1, 14)).renewal.ends_on
    assert_equal Date.new(2027, 2, 9), build_contract(from: Date.new(2027, 1, 1), to: Date.new(2027, 1, 20)).renewal.ends_on
  end

  def test_renewal_follows_on_with_the_same_length_and_envelopes
    contract = contract(from: Date.new(2027, 1, 1), to: Date.new(2027, 6, 30),
                        envelopes: [{name: "Dev", days: 10, activity_ids: [DEVELOPMENT], issue_privacy: "public"}])
    contract.envelopes.first.movements.create!(date: Date.new(2027, 3, 1), days: 4)
    renewal = contract.renewal
    assert_equal [Date.new(2027, 7, 1), Date.new(2027, 12, 31)], [renewal.starts_on, renewal.ends_on]
    assert_equal [contract.tracker_ids, false], [renewal.tracker_ids, renewal.include_subprojects]
    envelope = renewal.envelopes.first
    assert_equal ["Dev", 10, [DEVELOPMENT], "public", 0], [envelope.name, envelope.days, envelope.activity_ids, envelope.issue_privacy, envelope.movements.size]
    assert renewal.save
  end

  def test_time_is_charged_by_tracker_date_activity_and_privacy
    contract = contract(trackers: [BUG], from: Date.new(2027, 1, 1), to: Date.new(2027, 12, 31),
                        envelopes: [{name: "Dev", days: 10, activity_ids: [DEVELOPMENT], issue_privacy: "public"},
                                    {name: "Pilotage", days: 4, activity_ids: [DESIGN], issue_privacy: "private"},
                                    {name: "Other", days: 2, other_activities: true, issue_privacy: "public"}])
    bug = issue(@project, BUG)
    private_bug = issue(@project, BUG, is_private: true)
    log(bug, DEVELOPMENT, 8, Date.new(2027, 2, 1))
    log(bug, QA, 4, Date.new(2027, 2, 2))
    log(private_bug, DESIGN, 4, Date.new(2027, 2, 3))
    # Not charged: internal private development, another tracker, outside the dates, no issue.
    log(private_bug, DEVELOPMENT, 8, Date.new(2027, 2, 4))
    log(issue(@project, FEATURE), DEVELOPMENT, 8, Date.new(2027, 2, 5))
    log(bug, DEVELOPMENT, 8, Date.new(2028, 1, 1))
    TimeEntry.create!(project: @project, user: @administrator, activity_id: DEVELOPMENT, hours: 8, spent_on: Date.new(2027, 2, 6))
    assert_equal({"Dev" => 1.0, "Pilotage" => 0.5, "Other" => 0.5}, charged(contract))
  end

  def test_project_specific_activities_count_as_their_parent
    override = TimeEntryActivity.create!(name: "Development", parent_id: DEVELOPMENT, project: @project, active: true)
    contract = contract(envelopes: [{name: "Dev", days: 10, activity_ids: [DEVELOPMENT]}])
    log(issue(@project, BUG), override.id, 4, Date.new(2027, 2, 1))
    assert_equal({"Dev" => 0.5}, charged(contract))
  end

  def test_subprojects_count_unless_a_closer_contract_covers_them
    parent = contract(trackers: [BUG, FEATURE], subprojects: true)
    child = contract(project: @child, trackers: [FEATURE], from: Date.new(2027, 1, 1), to: Date.new(2027, 6, 30))
    log(issue(@child, BUG), DEVELOPMENT, 8, Date.new(2027, 2, 1))
    child_feature = issue(@child, FEATURE)
    log(child_feature, DEVELOPMENT, 8, Date.new(2027, 2, 2))
    # After the child's contract, its features go back to the parent's.
    log(child_feature, DEVELOPMENT, 4, Date.new(2027, 7, 1))
    log(issue(@grandchild, FEATURE), DEVELOPMENT, 8, Date.new(2027, 3, 1))
    assert_equal({"All" => 2.5}, charged(parent))
    assert_equal({"All" => 1.0}, charged(child))
    # Without include_subprojects, the subprojects keep their time.
    parent.update!(include_subprojects: false)
    assert_equal({"All" => 0.0}, charged(parent))
  end

  def test_hours_per_day_follow_each_project
    ReportingProjectSetting.update_for(@child, hours_per_day: 4)
    contract = contract(subprojects: true)
    log(issue(@project, BUG), DEVELOPMENT, 8, Date.new(2027, 2, 1))
    log(issue(@child, BUG), DEVELOPMENT, 8, Date.new(2027, 2, 1))
    assert_equal({"All" => 3.0}, charged(contract))
  end

  def test_a_period_opens_with_the_balance_of_its_first_day
    contract = contract(from: Date.new(2027, 1, 15), to: Date.new(2027, 12, 31))
    envelope = contract.envelopes.first
    envelope.movements.create!(date: Date.new(2027, 7, 1), days: 5, comment: "Amendment")
    bug = issue(@project, BUG)
    log(bug, DEVELOPMENT, 24, Date.new(2027, 3, 10))
    log(bug, DEVELOPMENT, 16, Date.new(2027, 8, 10))
    account = account(contract)
    ledger = account.envelope_ledger(envelope, Date.new(2027, 7, 1), Date.new(2027, 9, 30))
    assert_equal [7, 5, 2, 10], [ledger.opening_balance, ledger.granted, ledger.consumed, ledger.remaining]
    # The months before the contract are left out, and nothing is granted after its end.
    full = account.ledger(Date.new(2026, 11, 1), Date.new(2028, 3, 31))
    assert_equal ["2027-01-15", 12], [full.rows.first.period.first_day.iso8601, full.rows.length]
    assert_equal [15, 5, 10], [full.granted, full.consumed, full.remaining]
    assert_nil account.ledger(Date.new(2028, 1, 1), Date.new(2028, 3, 31))
    assert_equal 10, account.closing_balance(envelope)
  end

  def test_carried_over_days_point_back_to_their_envelope
    previous = contract(from: Date.new(2027, 1, 1), to: Date.new(2027, 12, 31))
    renewal = previous.renewal
    renewal.envelopes.first.movements.build(date: renewal.starts_on, days: 3, comment: "Carry-over",
                                            source_envelope: previous.envelopes.first)
    renewal.save!
    assert_equal 3, account(previous).carried_out(previous.envelopes.first.reload)
    previous.destroy
    assert_nil renewal.envelopes.first.movements.first.reload.source_envelope_id
  end

  private

  def build_contract(project: @project, trackers: [BUG], from: Date.new(2027, 1, 1), to: Date.new(2027, 12, 31), subprojects: false,
                     envelopes: [{name: "All", days: 10, other_activities: true}])
    contract = ReportingCreditContract.new(project: project, name: "TMA", starts_on: from, ends_on: to, tracker_ids: trackers,
                                           include_subprojects: subprojects)
    envelopes.each_with_index { |attributes, index| contract.envelopes.build(attributes.merge(position: index)) }
    contract
  end

  def contract(**options)
    build_contract(**options).tap(&:save!)
  end

  def issue(project, tracker_id, **attributes)
    create_issue(project, tracker: Tracker.find(tracker_id), **attributes)
  end

  def log(issue, activity_id, hours, date)
    TimeEntry.create!(project: issue.project, issue: issue, user: @administrator, activity_id: activity_id, hours: hours, spent_on: date)
  end

  def account(contract)
    contract = ReportingCreditContract.includes(envelopes: [:movements, :carried_movements]).find(contract.id)
    scope = RedmineReporting::CreditScope.for_projects([contract.project])
    hours = ReportingProjectSetting.hours_by_project(contract.project.self_and_descendants.to_a)
    RedmineReporting::CreditContractAccount.new(contract, scope: scope, hours: hours)
  end

  # Days charged to each envelope over the whole contract.
  def charged(contract)
    account = account(contract)
    account.envelopes.to_h { |envelope| [envelope.name, account.spent_days(envelope).values.sum] }
  end
end
