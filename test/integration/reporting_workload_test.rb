# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_workload_test.rb
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

class ReportingWorkloadTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  setup do
    ReportingProjectSetting.create!(project: @project, section_ids: %w[workload], run_tracker_ids: [999_999])
    @parent_issue.update_columns(assigned_to_id: @administrator.id, estimated_hours: 4)
    @child_issue.update_columns(estimated_hours: 5)
  end

  def dashboard(user = @administrator, **parameters)
    session = authenticated_session(user)
    session.get "/projects/#{@project.identifier}/reporting", params: {section: "workload", **parameters}
    assert_equal 200, session.response.status
    refute_includes session.response.body, "translation missing"
    page = Nokogiri::HTML(session.response.body)
    [JSON.parse(page.at_css("#report-data").text).fetch("workload"), page, session]
  end

  def test_current_assignments_are_separate_from_period_contributions_and_run_scope
    old = Date.current - 100
    @entry.update_columns(spent_on: old)
    data, page, session = dashboard(from: Date.current, to: Date.current)
    assert_equal 2, data.fetch("assignees").sum { |row| row.fetch("count") }
    assert_equal 7, data.fetch("remaining").sum { |row| row.fetch("hours") }
    assert_equal 1, data.fetch("contributors").sum { |row| row.fetch("hours") }
    assert_equal "workload", page.at_css('input[name="section"]')["value"]
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "workload", assignee_id: "none", open: "true", workload_effort: "true", times: "true"}
    session.follow_redirect!
    assert_equal [@child_issue.id.to_s], Nokogiri::HTML(session.response.body).css("table.issues td.id a").map(&:text)
  end

  def test_groups_inactive_assignees_unestimated_issues_and_overruns
    group = Group.create!(lastname: "Reporting workload group")
    @parent_issue.update_columns(assigned_to_id: group.id, estimated_hours: nil)
    @child_issue.update_columns(assigned_to_id: @administrator.id, estimated_hours: 1)
    # Keep the viewer active; use a locked assignee to check the payload independently.
    locked = create_viewer
    locked.update!(status: User::STATUS_LOCKED)
    @child_issue.update_columns(assigned_to_id: locked.id)
    data, = dashboard
    assert_equal [group.id, locked.id].sort, data.fetch("assignees").map { |row| row["id"] }.sort
    assert_equal 1, data.fetch("assignees").sum { |row| row["unestimated"] }
    assert_equal 0, data.fetch("remaining").sum { |row| row["hours"] }
  end

  def test_issue_only_viewer_cannot_receive_time_data_or_private_project_issues
    viewer = create_viewer
    viewer.roles_for_project(@project).each { |role| role.remove_permission!(:view_time_entries) }
    private_issue = create_issue(@project, is_private: true)
    data, page, session = dashboard(viewer)
    assert_equal 1, data.fetch("assignees").sum { |row| row["count"] }
    refute data.key?("remaining")
    refute data.key?("contributors")
    refute page.at_css("#tab-team_activity")
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "workload", assignee_id: "none", open: "true"}
    session.follow_redirect!
    ids = Nokogiri::HTML(session.response.body).css("table.issues td.id a").map(&:text)
    refute_includes ids, @child_issue.id.to_s
    refute_includes ids, private_issue.id.to_s
  end

  def test_remaining_excludes_projects_without_time_permission_and_its_list_matches
    @project.disable_module!(:time_tracking)
    data, _, session = dashboard
    assert_equal 2, data.fetch("assignees").sum { |row| row["count"] }
    assert_equal [nil], data.fetch("remaining").map { |row| row["id"] }
    assert_equal 3, data.fetch("remaining").first["hours"]
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "workload", assignee_id: @administrator.id, open: "true", workload_effort: "true"}
    session.follow_redirect!
    assert_empty Nokogiri::HTML(session.response.body).css("table.issues td.id a")
  end

  def test_time_only_modules_render_activity_without_issue_payload
    [@project, @child].each { |project| project.disable_module!(:issue_tracking) }
    data, page, = dashboard(from: Date.current, to: Date.current)
    assert_equal %w[contributors mix], data.keys.sort
    assert_equal 3, data["contributors"].sum { |row| row["hours"] }
    assert page.at_css("#panel-team_activity")
    refute page.at_css("#tab-workload")
  end

  def test_closed_issues_filters_and_empty_scope
    @child_issue.update_columns(status_id: IssueStatus.where(is_closed: true).first!.id)
    data, = dashboard
    assert_equal 1, data["assignees"].sum { |row| row["count"] }
    data, = dashboard(f: ["project_id"], op: {"project_id" => "="}, v: {"project_id" => [@outside.id.to_s]})
    assert data.except("mix").values.all?(&:empty?)
    assert_equal 0, data["mix"].sum { |row| row["hours"] }
    anonymous = ActionDispatch::Integration::Session.new(Rails.application)
    anonymous.get "/projects/#{@project.identifier}/reporting", params: {section: "workload"}
    assert_equal 302, anonymous.response.status
  end
  def test_work_mix_includes_all_four_categories_and_matches_native_lists
    run, build, other = Tracker.order(:id).first(3)
    @project.trackers = [run, build, other]
    @child.trackers = [run, build, other]
    ReportingProjectSetting.update_for(@project, run_tracker_ids: [run.id], build_tracker_ids: [build.id])
    @parent_issue.update_columns(tracker_id: run.id)
    @child_issue.update_columns(tracker_id: build.id)
    third = create_issue(@project, tracker: other)
    [@parent_issue, third].each_with_index do |issue, index|
      TimeEntry.create!(project: @project, issue: issue, user: @administrator, activity: @entry.activity, hours: index + 3, spent_on: Date.current)
    end
    data, _, session = dashboard(from: Date.current, to: Date.current)
    assert_equal [3, 2, 4, 1], data["mix"].map { |row| row["hours"] }
    data["mix"].each do |row|
      session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "workload", records: "time_entries", work_role: row["role"], from: Date.current, to: Date.current}
      session.follow_redirect!
      assert_equal 200, session.response.status
      assert_equal 1, Nokogiri::HTML(session.response.body).css("table.time-entries tbody tr").size, row["role"]
    end
    data, = dashboard(from: Date.current, to: Date.current, f: ["tracker_id"], op: {"tracker_id" => "="}, v: {"tracker_id" => [build.id.to_s]})
    assert_equal [0, 2, 0, 0], data["mix"].map { |row| row["hours"] }
  end

end
