# frozen_string_literal: true

require_relative "../test_helper"

class ReportingDrilldownTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_issue_selection_uses_native_filters_and_preserves_subprojects
    query = native_query(created_from: Date.current.iso8601, created_to: Date.current.iso8601)
    assert_equal [@parent_issue.id, @child_issue.id].sort, query.issue_ids.sort
    assert_equal "><", query.operator_for("created_on")
    refute query.has_filter?("issue_id")
  end

  def test_chart_selection_intersects_existing_filters
    reporting_query = build_query
    reporting_query.add_filter("tracker_id", "!", [@tracker.id.to_s])
    query = native_query({tracker: @tracker.name}, reporting_query)
    assert_empty query.issue_ids
  end

  def test_empty_or_invalid_project_scope_never_expands_to_other_projects
    reporting_query = build_query
    reporting_query.add_filter("project_id", "=", [@outside.id.to_s])
    assert_empty native_query({}, reporting_query).issue_ids
    reporting_query.add_filter("tracker_id", "invalid", [@tracker.id.to_s])
    assert_empty native_query({}, reporting_query).issue_ids
  end

  def test_historical_backlog_includes_open_issues_and_later_closures
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 1), closed_on: nil)
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 1), closed_on: Time.utc(2026, 2, 1))
    query = native_query(backlog_at: "2026-01-15")
    assert_equal [@parent_issue.id, @child_issue.id].sort, query.issue_ids.sort
    @child_issue.update_columns(closed_on: Time.utc(2026, 1, 15, 23, 59))
    assert_equal [@parent_issue.id], query.issue_ids
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 16))
    assert_empty query.issue_ids
  end

  def test_flow_selection_includes_issues_created_or_closed_in_the_period
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: nil)
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 20))
    query = native_query(flow_from: "2026-01-01", flow_to: "2026-01-31")
    assert_equal [@parent_issue.id, @child_issue.id].sort, query.issue_ids.sort
    assert_equal "><", query.operator_for("reporting_flow_on")
    @child_issue.update_columns(closed_on: Time.utc(2026, 2, 1))
    assert_equal [@parent_issue.id], query.issue_ids
  end

  def test_month_selection_deduplicates_an_issue_created_and_closed_in_that_month
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20))
    @child_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: nil)
    query = native_query(flow_from: "2026-01-01", flow_to: "2026-01-31")
    assert_equal [@parent_issue.id], query.issue_ids
  end

  def test_closed_selection_leaves_reopened_issues_out
    @parent_issue.update_columns(closed_on: Time.utc(2026, 1, 20), status_id: IssueStatus.where(is_closed: true).first!.id)
    # Reopened: Redmine keeps its closed_on.
    @child_issue.update_columns(closed_on: Time.utc(2026, 1, 21))
    assert_equal [@parent_issue.id, @child_issue.id].sort, native_query(closed_from: "2026-01-01", closed_to: "2026-01-31").issue_ids.sort
    assert_equal [@parent_issue.id], native_query(closed_from: "2026-01-01", closed_to: "2026-01-31", closed: "true").issue_ids
  end

  def test_remaining_time_selection_lists_estimated_and_spent_totals
    uri = URI(RedmineReporting::Drilldown.build(build_query, {times: "true"}).path)
    parameters = Rack::Utils.parse_nested_query(uri.query)
    assert_equal %w[estimated_hours spent_hours], parameters["t"]
    assert_equal %w[estimated_hours spent_hours], parameters["c"].last(2)
    refute_includes URI(RedmineReporting::Drilldown.build(build_query, {}).path).query, "spent_hours"
  end

  def test_open_status_selection_does_not_override_a_status_exclusion
    reporting_query = build_query
    reporting_query.add_filter("status_id", "!", IssueStatus.where(is_closed: false).ids.map(&:to_s))
    assert_empty native_query({open: "true"}, reporting_query).issue_ids
  end

  def test_age_bucket_has_exact_inclusive_boundaries
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 24))
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 25))
    assert_equal [@parent_issue.id], native_query(age: "7-30", as_of: "2026-01-31", open: "true").issue_ids
  end

  def test_time_entries_keep_unassigned_time_and_use_spent_dates
    query = native_query(records: "time_entries", from: Date.current.iso8601, to: Date.current.iso8601)
    assert_equal [@entry.id, @unassigned_entry.id].sort, time_entry_ids(query)
    assert_equal "><", query.operator_for("spent_on")
  end

  def test_time_entry_priority_filter_is_applied_by_redmine
    reporting_query = build_query
    reporting_query.add_filter("priority_id", "=", [@child_issue.priority_id.to_s])
    query = native_query({records: "time_entries"}, reporting_query)
    assert_equal [@entry.id], time_entry_ids(query)
    assert query.has_filter?("issue.priority_id")
  end

  def test_time_entry_missing_version_excludes_unassigned_time
    reporting_query = build_query
    reporting_query.add_filter("fixed_version_id", "!*", [""])
    query = native_query({records: "time_entries"}, reporting_query)
    assert_empty time_entry_ids(query)
    @child_issue.update_columns(fixed_version_id: nil)
    assert_equal [@entry.id], time_entry_ids(query)
  end

  def test_user_selection_includes_inactive_contributors
    @administrator.update_columns(status: User::STATUS_LOCKED)
    query = native_query(records: "time_entries", user: @administrator.name)
    assert_equal [@entry.id, @unassigned_entry.id].sort, time_entry_ids(query)
  end

  private

  def native_query(parameters = {}, reporting_query = build_query)
    path = RedmineReporting::Drilldown.build(reporting_query, parameters).path
    uri = URI(path)
    query_class = parameters[:records] == "time_entries" ? TimeEntryQuery : IssueQuery
    assert_equal(query_class == TimeEntryQuery ? "/time_entries" : "/issues", uri.path)
    query = query_class.new(name: "Reporting")
    query.build_from_params(Rack::Utils.parse_nested_query(uri.query).with_indifferent_access)
    assert query.valid?, query.errors.full_messages.join(", ")
    query
  end

  def time_entry_ids(query)
    query.results_scope.reorder(nil).pluck("time_entries.id").sort
  end
end
