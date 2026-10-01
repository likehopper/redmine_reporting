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
    assert_equal [{label: @tracker.name, data: [1, 1]}], backlog[:trackerSeries]
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
  def test_consumption_follows_the_selected_period_from_the_carried_over_credit
    credit(@project, 10)
    @entry.update_columns(spent_on: Date.new(2025, 6, 1))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 3, 10), hours: 24)
    TimeEntry.create!(project: @project, user: @administrator, activity: TimeEntryActivity.active.first!, hours: 16,
                      spent_on: Date.new(2026, 9, 5))
    consumption = report(Date.new(2026, 7, 1), Date.new(2026, 12, 31))[:consumption]
    assert_equal({opening: 7.0, granted: 0.0, available: 7.0, consumed: 2.0, remaining: 5.0, progress: 29},
                 consumption.dig(:period, :totals))
    assert_equal 6, consumption.dig(:period, :labels).length
    assert_equal [7.0, 7.0, 5.0], consumption.dig(:period, :credit).values_at(0, 1, 2)
    # The contract view starts with the contract.
    assert_equal "2026-01-01", consumption.dig(:contract, :periodStarts).first
  end

  def test_time_logged_before_the_contract_start_is_not_charged
    credit(@project, 10, active_from: Date.new(2026, 3, 1))
    @entry.update_columns(spent_on: Date.new(2025, 6, 1))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 2, 10), hours: 8)
    totals = report(Date.new(2026, 1, 1), Date.new(2026, 3, 31)).dig(:consumption, :period, :totals)
    assert_equal({opening: 0.0, granted: 10.0, available: 10.0, consumed: 0.0, remaining: 10.0, progress: 0}, totals)
  end

  def test_consumption_cumulates_subproject_accounts_and_lists_each_subproject
    credit(@project, 20)
    credit(@child, 10)
    @entry.update_columns(spent_on: Date.new(2026, 1, 20))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 2, 10), hours: 4)
    consumption = report(Date.new(2026, 2, 1), Date.new(2026, 2, 28))[:consumption]

    # The child's January time was charged before the period: it comes in the carried-over credit.
    assert_equal({opening: 29.75, granted: 0.0, available: 29.75, consumed: 0.5, remaining: 29.25, progress: 2},
                 consumption.dig(:period, :totals))
    assert_equal [30.0, 0.0], consumption.dig(:contract, :grants)
    assert_equal [0.25, 0.5], consumption.dig(:contract, :spent)
    rows = consumption[:projects].map { |row| row.except(:id, :identifier) }
    assert_equal [{name: @project.name, own: true, opening: 20.0, granted: 0.0, available: 20.0, consumed: 0.5, remaining: 19.5, progress: 3},
                  {name: @child.name, own: false, opening: 9.75, granted: 0.0, available: 9.75, consumed: 0.0, remaining: 9.75, progress: 0}],
                 rows
  end

  def test_subproject_report_only_counts_its_own_subtree
    credit(@project, 20)
    credit(@child, 10)
    query = ReportingQuery.new(name: "Reporting", project: @child, user: @administrator)
    consumption = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).
      build[:consumption]
    assert_equal 10, consumption.dig(:period, :totals, :available)
    # A single project needs no breakdown.
    assert_empty consumption[:projects]
  end

  def test_nested_subproject_balances_match_without_sharing_debt
    grandchild = create_project("reporting-query-grandchild", parent: @child)
    [@project, @child, grandchild].each(&:reload)
    credit(@child, 10)
    credit(grandchild, 1)
    TimeEntry.create!(project: grandchild, user: @administrator, activity: TimeEntryActivity.active.first!,
                      hours: 16, spent_on: Date.new(2026, 1, 15))
    parent_report = report(Date.new(2026, 1, 1), Date.new(2026, 1, 31))[:consumption]
    child_query = ReportingQuery.new(name: "Reporting", project: @child, user: @administrator)
    child_report = RedmineReporting::ReportBuilder.new(query: child_query,
      first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).build[:consumption]
    assert_equal 10.0, child_report.dig(:period, :totals, :remaining)
    child_row = parent_report[:projects].find { |row| row[:id] == @child.id }
    child_report.dig(:period, :totals).each { |key, value| assert_equal value, child_row.fetch(key), key.to_s }
    assert_equal child_report.dig(:period, :credit), parent_report.dig(:period, :credit)
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

  def credit(project, days, active_from: Date.new(2026, 1, 1))
    ReportingCreditPolicy.create!(project: project, tracker: @tracker, name: "TMA", initial_credit_days: days,
                                  anniversary_month: active_from.month, anniversary_day: active_from.day, active_from: active_from)
  end
end
