# Regression cases discovered during release review.
require_relative '../test_helper'

class ReportingRegressionsTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def test_reopened_summary_and_native_list_agree
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20))
    query = build_query
    query.add_filter('project_id', '=', [@project.id.to_s])
    first = Date.new(2026, 3, 1)
    last = Date.new(2026, 3, 31)
    summary = RedmineReporting::ReportBuilder.new(query: query, first_day: first, last_day: last).build.fetch(:summary)
    path = RedmineReporting::Drilldown.build(query, {records: 'issues', created_to: last.iso8601,
      closed_before: (first - 1).iso8601, open: 'true'}).path
    native = IssueQuery.new(name: 'Audit')
    native.build_from_params(Rack::Utils.parse_nested_query(URI(path).query).with_indifferent_access)
    assert_equal summary[:openIssues], native.issue_count
  end

  def test_hidden_consumption_does_not_publish_credit_amounts
    viewer = create_viewer
    viewer.members.first.roles.first.update!(permissions: [:view_reporting, :view_issues])
    @project.reporting_credit_policies.create!(tracker: @tracker, name: 'Confidential budget',
      initial_credit_days: 123, anniversary_month: 1, anniversary_day: 1)
    session = authenticated_session(viewer)
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML5(session.response.body)
    assert_nil page.at_css('#tab-consumption')
    report = JSON.parse(page.at_css('#report-data').text)
    assert_nil report['consumption']
  end

  def test_current_backlog_contains_a_reopened_issue
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20))
    timeline = RedmineReporting::IssueTimeline.new(@parent_issue, @administrator)
    refute timeline.closed?
    assert timeline.in_backlog_on?(Date.new(2026, 3, 31))
  end
  def test_last12_credit_matches_contract_closing_balance
    @project.reporting_credit_policies.create!(tracker: @tracker, name: 'Annual budget',
      initial_credit_days: 100, anniversary_month: 1, anniversary_day: 1, active_from: Date.new(2025, 1, 1))
    report = RedmineReporting::ReportBuilder.new(query: build_query,
      first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 3, 31)).build.fetch(:consumption)
    assert_equal report[:contract][:credit].last, report[:last12][:credit].last
  end

  def test_subproject_consumption_matches_its_own_report
    @child.reporting_credit_policies.create!(tracker: @tracker, name: 'Child budget',
      initial_credit_days: 100, anniversary_month: 1, anniversary_day: 1, active_from: Date.current.beginning_of_year)
    ReportingProjectSetting.create!(project: @child, hours_per_day: 4)
    root_report = RedmineReporting::ReportBuilder.new(query: build_query,
      first_day: Date.current.beginning_of_year, last_day: Date.current, hours_per_day: 8).build.fetch(:consumption)
    child_query = ReportingQuery.new(name: 'Reporting', project: @child, user: @administrator)
    child_report = RedmineReporting::ReportBuilder.new(query: child_query,
      first_day: Date.current.beginning_of_year, last_day: Date.current, hours_per_day: 4).build.fetch(:consumption)
    branch = root_report[:projects].find { |project| project[:id] == @child.id }
    assert_equal child_report[:contract][:cumulativeSpent].last, branch[:consumed]
  end

  def test_invalid_and_excessive_periods_are_rejected_without_report_data
    session = authenticated_session(@administrator)
    [["1900-01-01", "2200-01-01", "day"], ["2026-02-30", "2026-03-01", "month"],
     ["0001-01-01", "2026-01-01", "month"]].each do |from, to, grouping|
      session.get "/projects/#{@project.identifier}/reporting", params: {from: from, to: to, grouping: grouping}
      assert_equal 422, session.response.status
      refute_includes session.response.body, 'id="report-data"'
    end
  end

  def test_child_credit_requires_time_and_reporting_permissions_on_that_child
    viewer = create_viewer
    @child.update!(is_public: true)
    @child.reporting_credit_policies.create!(tracker: @tracker, name: "Private child credit", initial_credit_days: 987,
      anniversary_month: 1, anniversary_day: 1)
    query = build_query(user: viewer)
    report = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.current.beginning_of_year, last_day: Date.current).build
    assert_equal 0, report[:consumption][:initialCredit]
  end

end
