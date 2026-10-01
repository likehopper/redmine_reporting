# frozen_string_literal: true
# File: redmine_reporting/test/unit/reporting_query_test.rb
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

class ReportingQueryTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_default_scope_includes_subprojects_and_unassigned_time
    query = build_query
    assert_equal [@parent_issue.id, @child_issue.id].sort, query.issue_scope.ids.sort
    assert_equal [@entry.id, @unassigned_entry.id].sort, query.time_entry_scope.ids.sort
  end

  def test_project_exclusion_is_shared_by_issues_and_time_entries
    query = build_query
    query.add_filter("project_id", "!", [@project.id.to_s])
    assert_equal [@child_issue.id], query.issue_scope.ids
    assert_equal [@entry.id], query.time_entry_scope.ids
  end

  def test_outside_project_id_cannot_expand_the_scope
    query = build_query
    query.add_filter("project_id", "=", [@outside.id.to_s])
    assert_empty query.issue_scope
    assert_empty query.time_entry_scope
  end

  def test_no_version_operator_and_exclusion_use_native_null_semantics
    query = build_query
    query.add_filter("fixed_version_id", "!*", [""])
    assert_equal [@parent_issue.id], query.issue_scope.ids
    assert_empty query.time_entry_scope
    query.add_filter("fixed_version_id", "!", [@version.id.to_s])
    assert_equal [@parent_issue.id], query.issue_scope.ids
  end

  def test_invalid_operator_returns_no_records
    query = build_query
    query.add_filter("tracker_id", "invalid", [@tracker.id.to_s])
    refute query.valid?
    assert_empty query.issue_scope
    assert_empty query.time_entry_scope
  end

  def test_native_parameters_round_trip_for_chart_links
    query = build_query
    query.add_filter("project_id", "!", [@project.id.to_s])
    query.add_filter("fixed_version_id", "*", [""])
    parameters = Rack::Utils.parse_nested_query(query.as_params.to_query).with_indifferent_access
    restored_query = build_query.build_from_params(parameters)
    assert_equal query.filters, restored_query.filters
    assert_equal query.issue_scope.ids, restored_query.issue_scope.ids
    assert_equal query.time_entry_scope.ids, restored_query.time_entry_scope.ids
  end

  def test_legacy_bookmarks_and_native_parameter_precedence
    query = build_query.build_from_params(project_ids: @child.id.to_s)
    assert_equal [@child_issue.id], query.issue_scope.ids
    query = build_query.build_from_params(f: ["project_id"], op: {"project_id" => "="},
                                         v: {"project_id" => [@project.id.to_s]}, project_ids: @outside.id.to_s)
    assert_equal [@parent_issue.id], query.issue_scope.ids
  end

  def test_private_subproject_options_and_records_are_hidden
    viewer = create_viewer
    query = build_query(user: viewer)
    assert_equal [@project.id], query.visible_projects.ids
    assert_equal [@parent_issue.id], query.issue_scope.ids
    assert_empty query.available_filters["fixed_version_id"].values
    query.add_filter("project_id", "=", [@child.id.to_s])
    assert_empty query.issue_scope
    assert_empty query.time_entry_scope
  end

  def test_anonymous_user_cannot_read_private_records
    query = build_query(user: User.anonymous)
    assert_empty query.issue_scope
    assert_empty query.time_entry_scope
    assert_empty query.available_filters["project_id"].values
  end

end
