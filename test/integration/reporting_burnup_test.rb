# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_burnup_test.rb
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

class ReportingBurnupTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  setup do
    ReportingProjectSetting.create!(project: @project, section_ids: %w[build], build_tracker_ids: [@tracker.id])
    @first = Date.current - 5
    @second_version = Version.create!(project: @child, name: "Next release")
    @open_status = IssueStatus.where(is_closed: false).first!
    @closed_status = IssueStatus.where(is_closed: true).first!
    @child_issue.update_columns(created_on: @first.to_time.utc + 3600, status_id: @open_status.id, fixed_version_id: nil, closed_on: (@first + 1).to_time.utc + 3600)
    transition(1, "status_id", @open_status.id, @closed_status.id)
    transition(2, "fixed_version_id", @version.id, @second_version.id)
    transition(3, "status_id", @closed_status.id, @open_status.id)
    transition(4, "fixed_version_id", @second_version.id, nil)
  end

  def transition(offset, field, old, value)
    journal = Journal.create!(journalized: @child_issue, user: @administrator, created_on: (@first + offset).to_time.utc + 3600)
    JournalDetail.create!(journal: journal, property: "attr", prop_key: field, old_value: old&.to_s, value: value&.to_s)
  end

  def test_burnup_replays_moves_unassignment_closures_and_reopenings
    query = build_query
    query.run_tracker_ids = [@tracker.id]
    query.section = "build"
    data = RedmineReporting::ReportBuilder.new(query: query, first_day: @first, last_day: @first + 4, grouping: "day").build[:burnup]
    a, b, unassigned = [@version.id, @second_version.id, nil].map { |id| data[:versions].find { |row| row[:id] == id } }
    assert_equal [1, 1, 0, 0, 0], a[:scope]
    assert_equal [0, 1, 0, 0, 0], a[:completed]
    assert_equal [0, 0, 1, 1, 0], b[:scope]
    assert_equal [0, 0, 1, 0, 0], b[:completed]
    assert_equal [0, 0, 0, 0, 1], unassigned[:scope]
    query.add_filter("fixed_version_id", "=", [@version.id.to_s])
    filtered = RedmineReporting::ReportBuilder.new(query: query, first_day: @first, last_day: @first + 4, grouping: "day").build[:burnup]
    assert_equal [a], filtered[:versions], "Current version filtering must not drop issues that moved out"
  end

  def test_native_historical_lists_match_each_version_and_completion
    session = authenticated_session(@administrator)
    [[0, @version.id, false, 1], [1, @version.id, true, 1], [2, @version.id, false, 0],
     [2, @second_version.id, true, 1], [3, @second_version.id, true, 0], [4, "none", false, 1]].each do |offset, version, completed, expected|
      session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "build", records: "issues", version_at: @first + offset, historical_version_id: version, completed: completed.to_s}
      assert_equal 302, session.response.status
      session.follow_redirect!
      assert_equal 200, session.response.status
      assert_equal expected, Nokogiri::HTML(session.response.body).css("table.issues td.id a").size, [offset, version, completed].inspect
    end
    session.get "/projects/#{@project.identifier}/reporting/details", params: {section: "build", records: "issues", version_at: @first + 1, historical_version_id: @version.id, completed: "true", f: ["fixed_version_id"], op: {"fixed_version_id" => "="}, v: {"fixed_version_id" => [@version.id.to_s]}}
    session.follow_redirect!
    assert_equal [@child_issue.id.to_s], Nokogiri::HTML(session.response.body).css("table.issues td.id a").map(&:text)
  end

  def test_future_visibility_and_empty_classification
    query = build_query(user: create_viewer)
    query.section = "build"
    query.run_tracker_ids = [@tracker.id]
    data = RedmineReporting::ReportBuilder.new(query: query, first_day: @first, last_day: Date.current + 5, grouping: "day").build[:burnup]
    assert_equal Date.current.iso8601, data[:dates].last
    refute data[:versions].any? { |row| [@version.id, @second_version.id].include?(row[:id]) }
    query.run_tracker_ids = []
    assert_empty RedmineReporting::ReportBuilder.new(query: query, first_day: @first, last_day: Date.current).build[:burnup][:versions]
  end

  def test_same_day_last_event_and_user_timezone
    @administrator.pref.time_zone = "Hawaii"
    @administrator.pref.save!
    query = build_query
    query.section = "build"
    query.run_tracker_ids = [@tracker.id]
    # 01:00 UTC is the previous local day. The SQL list and Ruby replay agree.
    date = @first
    data = RedmineReporting::ReportBuilder.new(query: query, first_day: date, last_day: date, grouping: "day").build[:burnup]
    assert_equal [1], data[:versions].find { |row| row[:id] == @version.id }[:completed]
    path = RedmineReporting::Drilldown.build(query, {records: "issues", version_at: date.iso8601, historical_version_id: @version.id.to_s, completed: "true"}).path
    native = IssueQuery.new(name: "History")
    native.build_from_params(Rack::Utils.parse_nested_query(URI(path).query).with_indifferent_access)
    assert_includes native.issues.map(&:id), @child_issue.id
  end
end
