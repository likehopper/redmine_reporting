# frozen_string_literal: true

require_relative "../test_helper"

class ReportingIssueFlowTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_creation_and_closure_are_independent_of_current_status
    closed_status = IssueStatus.where(is_closed: true).first!
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20), status_id: closed_status.id)
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 25))

    flow = issue_flow(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    assert_equal [1], flow[:opened]
    assert_equal [2], flow[:closed]
    assert_equal [{label: @tracker.name, opened: [1], closed: [-2]}], flow[:trackerFlow]
    assert_equal [{label: @parent_issue.priority.name, opened: [1], closed: [-2]}], flow[:priorityFlow]
  end

  def test_closure_in_a_later_month_does_not_move_the_creation
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 2, 5))
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: nil)

    flow = issue_flow(Date.new(2026, 1, 1), Date.new(2026, 2, 28))
    assert_equal [1, 0], flow[:opened]
    assert_equal [0, 1], flow[:closed]
    assert_equal [1, 0], flow[:trackerFlow].first[:opened]
    assert_equal [0, -1], flow[:trackerFlow].first[:closed]
  end

  def test_partial_month_only_counts_events_inside_the_selected_dates
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 16))
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 18), closed_on: Time.utc(2026, 1, 25))

    flow = issue_flow(Date.new(2026, 1, 15), Date.new(2026, 1, 20))
    assert_equal [1], flow[:opened]
    assert_equal [1], flow[:closed]
    assert_equal [1], flow[:trackerFlow].first[:opened]
    assert_equal [-1], flow[:trackerFlow].first[:closed]
  end

  def test_same_month_creation_and_closure_remain_visible_on_both_sides
    closed_status = IssueStatus.where(is_closed: true).first!
    [@parent_issue, @child_issue].each do |issue|
      issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20), status_id: closed_status.id)
    end
    flow = issue_flow(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    assert_equal [{label: @tracker.name, opened: [2], closed: [-2]}], flow[:trackerFlow]
    assert_equal [{label: @parent_issue.priority.name, opened: [2], closed: [-2]}], flow[:priorityFlow]
  end

  def test_each_tracker_and_priority_keeps_its_own_event_counts
    other_tracker = Tracker.where.not(id: @tracker.id).first!
    other_priority = IssuePriority.active.where.not(id: @parent_issue.priority_id).first!
    @child.trackers << other_tracker
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20))
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 20),
                                tracker_id: other_tracker.id, priority_id: other_priority.id)
    flow = issue_flow(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    tracker_groups = flow[:trackerFlow].index_by { |group| group[:label] }
    priority_groups = flow[:priorityFlow].index_by { |group| group[:label] }
    assert_equal [1], tracker_groups[@tracker.name][:opened]
    assert_equal [-1], tracker_groups[@tracker.name][:closed]
    assert_equal [0], tracker_groups[other_tracker.name][:opened]
    assert_equal [-1], tracker_groups[other_tracker.name][:closed]
    assert_equal [1], priority_groups[@parent_issue.priority.name][:opened]
    assert_equal [-1], priority_groups[@parent_issue.priority.name][:closed]
    assert_equal [0], priority_groups[other_priority.name][:opened]
    assert_equal [-1], priority_groups[other_priority.name][:closed]
  end

  def test_cumulative_flow_excludes_history_and_events_after_the_filter
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 1), closed_on: Time.utc(2026, 1, 10))
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 20), closed_on: Time.utc(2026, 2, 10))
    later_issue = create_issue(@project)
    later_issue.update_columns(created_on: Time.utc(2026, 2, 20), closed_on: Time.utc(2026, 2, 22))

    flow = issue_flow(Date.new(2026, 1, 15), Date.new(2026, 2, 15))
    assert_equal [1, 0], flow[:opened]
    assert_equal [0, 1], flow[:closed]
    assert_equal [1, 1], flow[:cumulativeCreated]
    assert_equal [0, 1], flow[:cumulativeClosed]
  end

  private

  def issue_flow(first_date, last_date)
    RedmineReporting::ReportBuilder.new(query: build_query, first_day: first_date, last_day: last_date).build.fetch(:issueFlow)
  end
end
