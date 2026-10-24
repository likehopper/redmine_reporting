# File: redmine_reporting/test/integration/reporting_regressions_test.rb
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
    contract!(@project, 'Confidential budget', 123)
    session = authenticated_session(viewer)
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML5(session.response.body)
    assert_nil page.at_css('#tab-consumption')
    report = JSON.parse(page.at_css('#report-data').text)
    assert_nil report['consumption']
    # The contract buttons still filter the page, without any amount.
    assert page.at_css('#reporting-contract-bar a.reporting-chip', text: 'Confidential budget')
    refute_includes session.response.body, '123'
  end

  def test_current_backlog_contains_a_reopened_issue
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 10), closed_on: Time.utc(2026, 1, 20))
    timeline = RedmineReporting::IssueTimeline.new(@parent_issue, @administrator)
    refute timeline.closed?
    assert timeline.in_backlog_on?(Date.new(2026, 3, 31))
  end
  def test_period_credit_matches_contract_closing_balance
    contract!(@project, 'Annual budget', 100, from: Date.new(2025, 7, 1), to: Date.new(2026, 6, 30))
    report = RedmineReporting::ReportBuilder.new(query: build_query,
      first_day: Date.new(2026, 1, 1), last_day: Date.new(2026, 3, 31)).build.fetch(:consumption)
    assert_equal report[:contract][:credit].last, report[:period][:credit].last
    assert_equal report[:contract][:credit].last, report[:period][:totals][:remaining]
  end

  def test_subproject_consumption_matches_its_own_report
    contract!(@child, 'Child budget', 100, from: Date.current.beginning_of_year, to: Date.current.end_of_year)
    ReportingProjectSetting.create!(project: @child, hours_per_day: 4)
    root_report = RedmineReporting::ReportBuilder.new(query: build_query,
      first_day: Date.current.beginning_of_year, last_day: Date.current, hours_per_day: 8).build.fetch(:consumption)
    child_query = ReportingQuery.new(name: 'Reporting', project: @child, user: @administrator)
    child_report = RedmineReporting::ReportBuilder.new(query: child_query,
      first_day: Date.current.beginning_of_year, last_day: Date.current, hours_per_day: 4).build.fetch(:consumption)
    branch = root_report[:contracts].find { |row| row[:project] == @child.name }
    # 2 h on the child at its own 4 h per day.
    assert_equal [0.5, 0.5], [branch[:consumed], child_report[:contract][:cumulativeSpent].last]
    assert_equal child_report[:period][:totals], branch.slice(*child_report[:period][:totals].keys)
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
    contract!(@child, "Private child credit", 987, from: Date.current.beginning_of_year, to: Date.current.end_of_year)
    query = build_query(user: viewer)
    report = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.current.beginning_of_year, last_day: Date.current).build
    assert_equal 0, report[:consumption][:period][:totals][:available]
    refute_includes query.contract_filter_values.map(&:first), "Private child credit"
  end

  private

  def contract!(project, name, days, from: Date.current.beginning_of_year, to: Date.current.end_of_year)
    ReportingCreditContract.create!(project: project, name: name, starts_on: from, ends_on: to, tracker_ids: [@tracker.id],
                                    envelopes_attributes: [{name: "All", days: days, other_activities: true}])
  end

end
