# frozen_string_literal: true

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
    # The closed child's 2 h are left out of the time left: only open issues count.
    assert_equal({issues: 2, openIssues: 1, closedIssues: 1, closedRatio: 50, spentDays: 0.0,
                  estimatedHours: 10.0, issueSpentHours: 0.0, remainingDays: 1.25, spentRatio: 0}, summary)
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

  def test_consumption_cumulates_subproject_credits_and_lists_each_subproject
    credit(@project, 20)
    credit(@child, 10)
    @entry.update_columns(spent_on: Date.new(2026, 1, 20))
    @unassigned_entry.update_columns(spent_on: Date.new(2026, 2, 10), hours: 4)
    consumption = report(Date.new(2026, 2, 1), Date.new(2026, 2, 28))[:consumption]

    assert_equal 30, consumption[:initialCredit]
    assert_equal [30.0, 0.0], consumption.dig(:contract, :grants)
    assert_equal [0.25, 0.5], consumption.dig(:contract, :spent)
    # The last 12 months reach back before the report's first day.
    assert_equal 12, consumption.dig(:last12, :labels).length
    assert_equal 0.25, consumption.dig(:last12, :spent)[10]
    rows = consumption[:projects].map { |row| row.slice(:name, :own, :granted, :consumed, :remaining, :progress) }
    assert_equal [{name: @project.name, own: true, granted: 20.0, consumed: 0.5, remaining: 19.5, progress: 3},
                  {name: @child.name, own: false, granted: 10.0, consumed: 0.25, remaining: 9.75, progress: 3}], rows
  end

  def test_subproject_report_only_counts_its_own_subtree
    credit(@project, 20)
    credit(@child, 10)
    query = ReportingQuery.new(name: "Reporting", project: @child, user: @administrator)
    consumption = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 1, 31)).
      build[:consumption]
    assert_equal 10, consumption[:initialCredit]
    # A single project needs no breakdown.
    assert_empty consumption[:projects]
  end

  private

  def report(first_day, last_day, hours_per_day: 8)
    RedmineReporting::ReportBuilder.new(query: build_query, first_day: first_day, last_day: last_day, hours_per_day: hours_per_day).build
  end

  def credit(project, days)
    ReportingCreditPolicy.create!(project: project, tracker: @tracker, name: "TMA", initial_credit_days: days,
                                  anniversary_month: 1, anniversary_day: 1, active_from: Date.new(2026, 1, 1))
  end
end
