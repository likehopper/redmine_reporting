# frozen_string_literal: true
# File: redmine_reporting/test/unit/reporting_project_setting_test.rb
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

class ReportingProjectSettingTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_defaults_and_nearest_configured_ancestor
    setting = ReportingProjectSetting.for(@child)
    assert setting.new_record?
    assert_equal %w[run], setting.section_ids
    assert_equal 8, setting.hours_per_day
    parent = ReportingProjectSetting.create!(project: @project, hours_per_day: 7)
    assert_equal parent, ReportingProjectSetting.for(@child)
    assert parent.inherited_by?(@child)
    own = ReportingProjectSetting.create!(project: @child, hours_per_day: 6)
    assert_equal own, ReportingProjectSetting.for(@child)
    refute own.inherited_by?(@child)
  end

  def test_serialized_settings_keep_json_arrays_after_reload
    other = Tracker.where.not(id: @tracker.id).first!
    setting = ReportingProjectSetting.create!(project: @project, section_ids: %w[run],
                                               run_tracker_ids: [@tracker.id], build_tracker_ids: [other.id])
    setting.reload
    {section_ids: %w[run], run_tracker_ids: [@tracker.id], build_tracker_ids: [other.id]}.each do |attribute, expected|
      assert_equal expected, setting.public_send(attribute)
      assert_equal expected, JSON.parse(setting.read_attribute_before_type_cast(attribute))
    end
    setting.update!(section_ids: [], run_tracker_ids: [], build_tracker_ids: [])
    setting.reload
    %i[section_ids run_tracker_ids build_tracker_ids].each do |attribute|
      assert_equal [], setting.public_send(attribute)
    end
  end

  def test_validations_and_tracker_roles
    setting = ReportingProjectSetting.new(project: @project, hours_per_day: 0)
    refute setting.valid?
    assert setting.errors.key?(:hours_per_day)
    # Planned families cannot be enabled until their charts exist.
    setting.assign_attributes(hours_per_day: 7.5, section_ids: %w[run sla])
    refute setting.valid?
    assert setting.errors.key?(:section_ids)
    setting.section_ids = ["run", ""]
    setting.tracker_roles = {@tracker.id.to_s => "run", "999" => "build", "998" => ""}
    assert setting.valid?, setting.errors.full_messages.to_sentence
    assert_equal [@tracker.id], setting.run_tracker_ids
    assert_equal [999], setting.build_tracker_ids
    assert_equal "run", setting.tracker_role(@tracker)
  end

  def test_waiting_statuses_are_open_statuses_where_no_sla_delay_elapses
    open_ids = IssueStatus.where(is_closed: false).sorted.ids
    RedmineReporting::SlaSource.any_instance.stubs(:active_status_ids).returns(open_ids.drop(1))
    assert_equal open_ids.first(1), RedmineReporting::SlaSource.new(@project).waiting_status_ids
    RedmineReporting::SlaSource.any_instance.stubs(:active_status_ids).returns([])
    assert_equal open_ids, RedmineReporting::SlaSource.new(@project).waiting_status_ids
  end

  def test_sla_family_needs_the_plugin_configured_for_the_project
    source = RedmineReporting::SlaSource.new(@project)
    refute source.configured? unless Redmine::Plugin.installed?(:redmine_sla)
    sla = RedmineReporting::Sections::ALL.find { |section| section.id == "sla" }
    RedmineReporting::SlaSource.any_instance.stubs(:configured?).returns(false)
    refute RedmineReporting::Sections.available?(sla, @project)
    RedmineReporting::SlaSource.any_instance.stubs(:configured?).returns(true)
    assert RedmineReporting::Sections.available?(sla, @project)
    assert_equal %w[run build workload], RedmineReporting::Sections.selectable_ids
  end

  def test_visible_sections_follow_settings_and_permissions
    setting = ReportingProjectSetting.new(project: @project)
    assert_equal %w[run], RedmineReporting::Sections.visible(@project, @administrator, setting).map(&:id)
    assert_empty RedmineReporting::Sections.visible(@project, User.anonymous, setting)
    setting.section_ids = []
    assert_empty RedmineReporting::Sections.visible(@project, @administrator, setting)
  end

  def test_run_perimeter_keeps_unassigned_time_and_matches_native_lists
    other = Tracker.where.not(id: @tracker.id).first!
    @project.trackers << other
    build_issue = create_issue(@project, tracker: other)
    build_entry = TimeEntry.create!(project: @project, issue: build_issue, user: @administrator,
                                    activity: TimeEntryActivity.active.first!, hours: 3, spent_on: Date.current)
    query = build_query
    assert_includes query.issue_scope.ids, build_issue.id
    query.run_tracker_ids = [@tracker.id]
    assert_equal [@parent_issue.id, @child_issue.id].sort, query.issue_scope.ids.sort
    assert_equal [@entry.id, @unassigned_entry.id].sort, query.time_entry_scope.ids.sort
    refute_includes query.time_entry_scope.ids, build_entry.id
    assert query.tracker_restricted?
    # Drilldown lists apply the same perimeter as the charts.
    assert_equal query.issue_scope.ids.sort, native_ids(query, {})
    assert_equal query.time_entry_scope.ids.sort, native_ids(query, {records: "time_entries"})
  end

  def test_project_copy_and_deletion_carry_the_configuration
    ReportingProjectSetting.create!(project: @project, hours_per_day: 7, run_tracker_ids: [@tracker.id])
    policy = @project.reporting_credit_policies.create!(tracker: @tracker, name: "TMA", initial_credit_days: 12,
                                                        anniversary_month: 1, anniversary_day: 1)
    policy.reporting_credit_refills.create!(month: 7, day: 1, credit_days: 3)
    copy = Project.copy_from(@project)
    copy.name = "Reporting copy"
    copy.identifier = "reporting-copy"
    assert copy.copy(@project)
    copy.reload
    assert_equal 7, copy.reporting_project_setting.hours_per_day
    assert_equal [@tracker.id], copy.reporting_project_setting.run_tracker_ids
    assert_equal [[12, [3]]], copy.reporting_credit_policies.map { |item| [item.initial_credit_days, item.reporting_credit_refills.map(&:credit_days)] }
    assert_difference -> { ReportingProjectSetting.count } => -1, -> { ReportingCreditPolicy.count } => -1,
                      -> { ReportingCreditRefill.count } => -1 do
      copy.destroy
    end
  end

  private

  def native_ids(reporting_query, parameters)
    uri = URI(RedmineReporting::Drilldown.build(reporting_query, parameters).path)
    query = (parameters[:records] == "time_entries" ? TimeEntryQuery : IssueQuery).new(name: "Reporting")
    query.build_from_params(Rack::Utils.parse_nested_query(uri.query).with_indifferent_access)
    assert query.valid?, query.errors.full_messages.to_sentence
    query.is_a?(IssueQuery) ? query.issue_ids.sort : query.results_scope.reorder(nil).pluck("#{TimeEntry.table_name}.id").sort
  end
end
