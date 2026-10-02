# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_build_test.rb
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

class ReportingBuildTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def test_build_counts_versions_and_links_to_the_same_issues
    ReportingProjectSetting.create!(project: @project, section_ids: %w[run build], build_tracker_ids: [@tracker.id])
    @child_issue.update_columns(estimated_hours: 5, due_date: Date.current - 1)
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting", params: {section: "build"}
    assert_equal 200, session.response.status
    page = Nokogiri::HTML(session.response.body)
    refute_includes session.response.body, "translation missing"
    assert page.at_css("#panel-build #build-progress")
    report = JSON.parse(page.at_css("#report-data").text)
    rows = report.fetch("build").fetch("versions")
    version = rows.find { |row| row["id"] == @version.id }
    assert_equal 1, version.fetch("open")
    assert_equal 1, version.fetch("overdue")
    assert_equal 5, version.fetch("estimated")
    assert_equal 2, version.fetch("spent")
    assert_equal 3, version.fetch("remaining")
    assert_equal 0, version.fetch("overrun")
    assert_equal 2, rows.sum { |row| row.fetch("open") }
    assert_includes report.fetch("queryParams"), "section=build"
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "build", version_id: @version.id, open: "true"}
    session.follow_redirect!
    document = Nokogiri::HTML(session.response.body)
    assert_equal [@child_issue.id.to_s], document.css("table.issues tbody tr td.id a").map(&:text)
  end

  def test_build_without_classified_trackers_stays_empty_and_is_the_default_when_run_is_disabled
    ReportingProjectSetting.create!(project: @project, section_ids: %w[build], build_tracker_ids: [])
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML(session.response.body)
    assert page.at_css("#panel-build")
    assert_empty JSON.parse(page.at_css("#report-data").text).fetch("build").fetch("versions")
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "build"}
    session.follow_redirect!
    assert_empty Nokogiri::HTML(session.response.body).css("table.issues tbody tr td.id a")
  end

  def test_build_respects_private_projects_and_time_permissions
    ReportingProjectSetting.create!(project: @project, section_ids: %w[build], build_tracker_ids: [@tracker.id])
    viewer = create_viewer
    viewer.roles_for_project(@project).each { |role| role.remove_permission!(:view_time_entries) }
    session = authenticated_session(viewer)
    session.get "/projects/#{@project.identifier}/reporting", params: {section: "build"}
    assert_equal 200, session.response.status
    page = Nokogiri::HTML(session.response.body)
    rows = JSON.parse(page.at_css("#report-data").text).fetch("build").fetch("versions")
    assert_equal 1, rows.sum { |row| row.fetch("open") }
    refute rows.first.key?("spent")
    refute page.at_css("#build-charges")
    refute_includes session.response.body, @version.name
  end
  def test_build_time_scope_excludes_unassigned_and_other_trackers_and_keeps_overruns
    other = Tracker.where.not(id: @tracker.id).first!
    @project.trackers << other
    other_issue = create_issue(@project, tracker: other)
    TimeEntry.create!(project: @project, issue: other_issue, user: @administrator,
                      activity: TimeEntryActivity.active.first!, hours: 9, spent_on: Date.current)
    @child_issue.update_columns(estimated_hours: 1)
    query = build_query
    query.section = "build"
    query.run_tracker_ids = [@tracker.id]
    assert_equal [@entry.id], query.time_entry_scope.ids
    report = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.current, last_day: Date.current).build
    row = report.fetch(:build).fetch(:versions).find { |item| item[:id] == @version.id }
    assert_equal 0, row[:remaining]
    assert_equal 1, row[:overrun]
    query.run_tracker_ids = []
    assert_empty query.issue_scope
    assert_empty query.time_entry_scope
    assert_empty query.selected_tracker_ids
  end

  def test_unversioned_click_does_not_remove_an_existing_version_filter
    ReportingProjectSetting.create!(project: @project, section_ids: %w[build], build_tracker_ids: [@tracker.id])
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting/details", params: {
      section: "build", version_id: "none", f: ["fixed_version_id"],
      op: {"fixed_version_id" => "="}, v: {"fixed_version_id" => [@version.id.to_s]}}
    session.follow_redirect!
    assert_empty Nokogiri::HTML(session.response.body).css("table.issues tbody tr td.id a")
  end

end
