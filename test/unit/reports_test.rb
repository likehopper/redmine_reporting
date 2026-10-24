# frozen_string_literal: true
# File: redmine_reporting/test/unit/reports_test.rb
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

# Tab reports over real records: a parent project, its subproject and one issue in each.
class ReportsTest < ActiveSupport::TestCase
  include ReportingTestData

  def setup
    @closed_status = IssueStatus.where(is_closed: true).first!
  end

  def test_summary_counts_the_period_and_the_time_left_of_open_issues
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: nil, estimated_hours: 10)
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 20), status_id: @closed_status.id)
    summary = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:summary]
    # Both issues are estimated and done; only the open parent is left to do. The closed
    # child had no estimate: its 2 h are a negative gap. 10 − 2 = 10 (left) + (−2) (gap).
    assert_equal({issues: 2, openIssues: 1, closedIssues: 1, closedRatio: 50, spentDays: 0.0,
                  estimatedHours: 10.0, doneHours: 2.0, openEstimatedHours: 10.0, openDoneHours: 0.0,
                  estimatedDays: 1.25, doneDays: 0.25, remainingDays: 1.25, closedGapDays: -0.25,
                  progress: 17, unestimatedIssues: 1}, summary)
  end

  def test_work_figures_follow_the_status_filter
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), estimated_hours: 10)
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 5), closed_on: Time.utc(2026, 1, 25), status_id: @closed_status.id,
                                estimated_hours: 8)
    TimeEntry.create!(project: @project, issue: @parent_issue, user: @administrator, activity: TimeEntryActivity.active.first!,
                      hours: 4, spent_on: Date.new(2026, 1, 15))
    closed = summary_with_status(closed: true)
    # Closed issues: nothing left to do, fully done, and 8 h estimated against 2 h done.
    assert_equal [1, 1.0, 0.25, 0.0, 0.75, 100], closed.values_at(:issues, :estimatedDays, :doneDays, :remainingDays, :closedGapDays, :progress)
    open = summary_with_status(closed: false)
    assert_equal [1, 1.25, 0.5, 0.75, 0.0, 40], open.values_at(:issues, :estimatedDays, :doneDays, :remainingDays, :closedGapDays, :progress)
    all = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:summary]
    assert_equal all[:estimatedDays] - all[:doneDays], all[:remainingDays] + all[:closedGapDays]
  end

  def test_hours_per_day_convert_time_into_days
    @entry.update_columns(spent_on: Date.new(2026, 1, 15))
    assert_equal 0.5, report(Date.new(2026, 1, 1), Date.new(2026, 1, 31), hours_per_day: 4).dig(:summary, :spentDays)
  end

  def test_backlog_time_left_only_counts_time_logged_by_the_period_end
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), estimated_hours: 10)
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 20), status_id: @closed_status.id)
    backlog = report(Date.new(2026, 1, 1), Date.new(2026, 2, 28))[:backlog]
    # The child was closed on January 20: only the parent is left at each month end.
    assert_equal [{id: @tracker.id, label: @tracker.name, data: [1, 1]}], backlog[:trackerSeries]
    assert_equal [10.0, 10.0], backlog[:remainingTotal]
    @entry.update_columns(spent_on: Date.new(2026, 2, 5), issue_id: @parent_issue.id, project_id: @project.id)
    assert_equal [10.0, 8.0], report(Date.new(2026, 1, 1), Date.new(2026, 2, 28)).dig(:backlog, :remainingTotal)
  end

  def test_resolution_time_and_velocity_only_cover_issues_closed_over_the_period
    # Closed before the period: left out of the average.
    @parent_issue.update_columns(created_on: Time.utc(2025, 11, 1), closed_on: Time.utc(2025, 12, 20), status_id: @closed_status.id)
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20), status_id: @closed_status.id)
    # Reopened in the period: Redmine keeps its closed_on, but it is open again.
    reopened = create_issue(@project)
    reopened.update_columns(created_on: Time.utc(2026, 1, 2), closed_on: Time.utc(2026, 1, 25))
    # Closed after the period: loaded for other charts, but not a closure of the period.
    later = create_issue(@project)
    later.update_columns(created_on: Time.utc(2026, 1, 5), closed_on: Time.utc(2026, 2, 10), status_id: @closed_status.id)
    performance = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:performance]
    assert_equal [@child_issue.priority.name], performance[:resolutionLabels]
    assert_equal [@child_issue.priority_id], performance[:resolutionIds]
    assert_equal [10.0], performance[:resolutionDays]
    assert_equal [1], performance[:resolutionCounts]
    assert_equal [1], performance[:velocity]
  end

  def test_aging_counts_open_issues_by_age_at_the_period_end
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 28))
    @child_issue.update_columns(created_on: Time.utc(2025, 6, 1))
    performance = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:performance]
    assert_equal %w[lt7 7-30 30-90 90-180 gt180], performance[:agingKeys]
    assert_equal [1, 0, 0, 0, 1], performance[:agingValues]
  end

  def test_activity_groups_the_period_time_by_user_and_activity
    @entry.update_columns(spent_on: Date.new(2026, 1, 15))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 1, 16))
    TimeEntry.create!(project: @project, user: @administrator, activity: TimeEntryActivity.active.first!, hours: 5,
                      spent_on: Date.new(2026, 2, 1))
    activity = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:activity]
    assert_equal [@administrator.name], activity[:userLabels]
    assert_equal [3.0], activity[:userHours]
    assert_equal [TimeEntryActivity.active.first!.name], activity[:activityLabels]
  end

  # A 10-day yearly contract with 3 days used in the first half: a July-December report
  # starts with 7 days.
  def test_consumption_follows_the_selected_period_from_the_contract_balance
    contract(@project, 10)
    @entry.update_columns(spent_on: Date.new(2025, 6, 1))
    log(@parent_issue, 24, Date.new(2026, 3, 10))
    log(@parent_issue, 16, Date.new(2026, 9, 5))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 9, 5), hours: 8)
    consumption = report(Date.new(2026, 7, 1), Date.new(2026, 12, 31))[:consumption]
    assert_equal({opening: 7.0, granted: 0.0, available: 7.0, consumed: 2.0, remaining: 5.0, progress: 29},
                 consumption.dig(:period, :totals))
    assert_equal 6, consumption.dig(:period, :labels).length
    assert_equal [7.0, 7.0, 5.0], consumption.dig(:period, :credit).values_at(0, 1, 2)
    # Time without an issue is outside the contract; no parent contract here.
    assert_equal [1.0, nil], consumption[:period].values_at(:outside, :parent)
    assert_equal "2026-01-01", consumption.dig(:contract, :periodStarts).first
  end

  def test_a_contract_stops_at_its_end_and_the_next_starts_from_its_own_credit
    first = contract(@project, 10, from: Date.new(2026, 1, 1), to: Date.new(2026, 6, 30))
    renewal = first.renewal
    renewal.envelopes.first.days = 6
    renewal.envelopes.first.movements.build(date: renewal.starts_on, days: 3, source_envelope: first.envelopes.first)
    renewal.save!
    log(@parent_issue, 56, Date.new(2026, 2, 10))
    consumption = report(Date.new(2026, 1, 1), Date.new(2026, 12, 31))[:consumption]
    assert_equal({opening: 0.0, granted: 19.0, available: 19.0, consumed: 7.0, remaining: 9.0, progress: 37},
                 consumption.dig(:period, :totals))
    # June ends the first contract with 3 days; July starts the next one with 6 + 3.
    assert_equal [3.0, 9.0], consumption.dig(:period, :credit).values_at(5, 6)
    assert_equal [0.0, 3.0], consumption.dig(:period, :refills).values_at(5, 6)
    finished = consumption[:contracts].first
    assert_equal [true, 3.0, 3.0], finished.values_at(:ended, :closing, :carried)
    # The second one also ends with the period, with nothing carried yet.
    assert_equal [true, 9.0, 0.0], consumption[:contracts].last.values_at(:ended, :closing, :carried)
  end

  def test_consumption_adds_up_the_contracts_of_subprojects
    contract(@project, 20)
    contract(@child, 10)
    @entry.update_columns(spent_on: Date.new(2026, 1, 20))
    log(@parent_issue, 4, Date.new(2026, 2, 10))
    consumption = report(Date.new(2026, 2, 1), Date.new(2026, 2, 28))[:consumption]
    # The child's January time was charged before the period: it comes in its balance.
    assert_equal({opening: 29.75, granted: 0.0, available: 29.75, consumed: 0.5, remaining: 29.25, progress: 2},
                 consumption.dig(:period, :totals))
    assert_equal [30.0, 0.0], consumption.dig(:contract, :grants)
    assert_equal [0.25, 0.5], consumption.dig(:contract, :spent)
    rows = consumption[:contracts].map { |row| row.slice(:project, :own, :opening, :consumed, :remaining) }
    assert_equal [{project: @project.name, own: true, opening: 20.0, consumed: 0.5, remaining: 19.5},
                  {project: @child.name, own: false, opening: 9.75, consumed: 0.0, remaining: 9.75}], rows
  end

  def test_a_subproject_report_never_shows_its_parent_contract
    parent = contract(@project, 20, subprojects: true)
    @entry.update_columns(spent_on: Date.new(2026, 1, 15))
    child_query = ReportingQuery.new(name: "Reporting", project: @child, user: @administrator)
    child = RedmineReporting::ReportBuilder.new(query: child_query, first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).
      build[:consumption]
    assert_empty child[:contracts]
    assert_equal [0.0, 0.0, 0.25], [child.dig(:period, :totals, :available), child.dig(:period, :outside), child.dig(:period, :parent)]
    assert_equal [["Covered by the parent project", "parent"], ["Outside contract", "none"]], child_query.contract_filter_values
    parent_report = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:consumption]
    assert_equal [[parent.id, 0.25]], parent_report[:contracts].map { |row| row.values_at(:id, :consumed) }
  end

  def test_the_contract_filter_selects_time_and_issues_like_native_lists
    covered = contract(@project, 20)
    log(@parent_issue, 8, Date.new(2026, 1, 10))
    covered_entry = TimeEntry.order(:id).last
    {[covered.id.to_s] => [[@parent_issue.id], [covered_entry.id]],
     ["none"] => [[@child_issue.id], [@entry.id, @unassigned_entry.id].sort]}.each do |values, (issue_ids, entry_ids)|
      query = build_query
      query.add_filter("reporting_contract", "=", values)
      assert_equal issue_ids, query.issue_scope.ids.sort, values.inspect
      assert_equal entry_ids, query.time_entry_scope.ids.sort, values.inspect
      assert_equal issue_ids, native_ids(query, {}), values.inspect
      assert_equal entry_ids, native_ids(query, {records: "time_entries"}), values.inspect
    end
    # Private issues: the filter applies to issues and to their time alike.
    @parent_issue.update_columns(is_private: true)
    query = build_query
    query.add_filter("reporting_private", "=", ["1"])
    assert_equal [[@parent_issue.id], [covered_entry.id]], [query.issue_scope.ids, query.time_entry_scope.ids]
    query = build_query
    query.add_filter("reporting_private", "=", ["0"])
    assert_equal [@entry.id, @unassigned_entry.id].sort, query.time_entry_scope.ids.sort
    # Credit figures only count the selected contracts.
    query = build_query
    query.add_filter("reporting_contract", "=", ["none"])
    consumption = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).
      build[:consumption]
    assert_equal [[], 0.0], [consumption[:contracts], consumption.dig(:period, :totals, :available)]
  end

  private

  def report(first_day, last_day, hours_per_day: 8)
    RedmineReporting::ReportBuilder.new(query: build_query, first_day: first_day, last_day: last_day, hours_per_day: hours_per_day).build
  end

  # Statuses as the reporting form selects them: a list of open or closed statuses.
  def summary_with_status(closed:)
    query = build_query
    query.add_filter("status_id", "=", IssueStatus.where(is_closed: closed).ids.map(&:to_s))
    RedmineReporting::ReportBuilder.new(query: query, first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).build[:summary]
  end

  def contract(project, days, from: Date.new(2026, 1, 1), to: Date.new(2026, 12, 31), subprojects: false)
    ReportingCreditContract.create!(project: project, name: "TMA #{project.identifier}", starts_on: from, ends_on: to,
                                    tracker_ids: [@tracker.id], include_subprojects: subprojects,
                                    envelopes_attributes: [{name: "All", days: days, other_activities: true}])
  end

  def log(issue, hours, date)
    TimeEntry.create!(project: issue.project, issue: issue, user: @administrator, activity: TimeEntryActivity.active.first!,
                      hours: hours, spent_on: date)
  end

  def native_ids(reporting_query, parameters)
    uri = URI(RedmineReporting::Drilldown.build(reporting_query, parameters).path)
    query = (parameters[:records] == "time_entries" ? TimeEntryQuery : IssueQuery).new(name: "Reporting")
    query.build_from_params(Rack::Utils.parse_nested_query(uri.query).with_indifferent_access)
    assert query.valid?, query.errors.full_messages.to_sentence
    query.is_a?(IssueQuery) ? query.issue_ids.sort : query.results_scope.reorder(nil).pluck("#{TimeEntry.table_name}.id").sort
  end
end
