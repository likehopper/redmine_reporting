# frozen_string_literal: true
# File: redmine_reporting/test/unit/mirror_adapters_test.rb
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

# Runs only when Redmine Mirror is installed next to Reporting (COMPAT_MIRROR_PATH).
class ReportingMirrorAdaptersTest < ActiveSupport::TestCase
  include ReportingTestData

  # Source REST API double serving the read-only Reporting endpoints.
  class Source
    def initialize(responses)
      @responses = responses
    end

    def get(path, params = {})
      @responses.fetch(path).call(params)
    end
  end

  def setup
    skip "Redmine Mirror is not installed" unless Redmine::Plugin.installed?(:redmine_mirror)
    @store = RedmineMirror::DatabaseStore.new("reporting-test", project_id: @project.id)
    @second_tracker = Tracker.where.not(id: @tracker.id).first!
    @project.trackers << @second_tracker
    @mappings = {"tracker" => {"10" => @tracker.id.to_s, "20" => @second_tracker.id.to_s}}
  end

  def test_adapters_follow_the_mirror_contract
    %w[reporting_settings reporting_credit_policies].each do |key|
      adapter = RedmineMirror::REGISTRY[key]
      assert_kind_of RedmineReporting::MirrorAdapters::Base, adapter
      assert adapter.available?
      assert_equal "Reporting settings", I18n.t(adapter.label, locale: :en) if key == "reporting_settings"
    end
    # init.rb runs again after a code reload; registering twice is harmless.
    RedmineReporting::MirrorAdapters.register
    setting = MirrorProjectSetting.new(project: @project, source_url: "https://source.example", source_project_id: 7)
    assert_equal "/projects/#{@project.identifier}/reporting/credit_policies/3/edit",
                 RedmineMirror::REGISTRY["reporting_credit_policies"].local_path(3, @project)
    assert_equal "projects/7/settings/reporting", RedmineMirror::REGISTRY["reporting_settings"].remote_path(1, setting)
  end

  def test_settings_preview_import_rerun_update_and_local_change
    adapter = RedmineReporting::MirrorAdapters::Settings.new
    record = settings_record(hours_per_day: 6.0, section_ids: %w[run workload], run: [10], build: [20])

    assert_equal "create", sync(adapter, record, apply: false)[:action]
    assert_nil ReportingProjectSetting.find_by(project: @project), "a preview writes nothing"

    event = sync(adapter, record)
    setting = ReportingProjectSetting.find_by!(project: @project)
    assert_equal setting.id, event[:destination_id]
    assert_equal [6.0, %w[run workload], [@tracker.id], [@second_tracker.id]],
                 [setting.hours_per_day.to_f, setting.section_ids, setting.run_tracker_ids, setting.build_tracker_ids]
    assert_equal "unchanged", sync(adapter, record)[:action]

    record["hours_per_day"] = 7.5
    assert_equal "update", sync(adapter, record)[:action]
    assert_equal 7.5, setting.reload.hours_per_day.to_f

    setting.update!(hours_per_day: 5)
    error = assert_raises(RedmineMirror::Error) { sync(adapter, record) }
    assert_match(/Local modification/, error.message)
  end

  def test_settings_never_overwrite_or_copy_what_the_project_does_not_own
    adapter = RedmineReporting::MirrorAdapters::Settings.new
    ReportingProjectSetting.update_for(@project, hours_per_day: 4)
    error = assert_raises(RedmineMirror::Error) { sync(adapter, settings_record) }
    assert_match(/Existing local/, error.message)
    assert_equal 4, ReportingProjectSetting.find_by!(project: @project).hours_per_day

    inherited = settings_record.merge("inherited_from" => {"id" => 1, "name" => "Parent"})
    defaults = settings_record.merge("id" => nil)
    [inherited, defaults].each do |body|
      source = Source.new("projects/7/reporting/settings.json" => ->(_params) { {"reporting_setting" => body} })
      assert_empty adapter.records(source, 7)
    end
  end

  def test_unmapped_tracker_is_refused_before_writing
    adapter = RedmineReporting::MirrorAdapters::Settings.new
    assert_raises(RedmineMirror::Error) { sync(adapter, settings_record(run: [30])) }
    assert_nil ReportingProjectSetting.find_by(project: @project)
  end

  def test_credit_policies_import_with_refills_and_detect_local_changes
    adapter = RedmineReporting::MirrorAdapters::CreditPolicies.new
    record = policy_record(refills: [refill(10, 1, 3, "2026-01-01"), refill(4, 1, 2.5)])

    assert_equal "create", sync(adapter, record, apply: false)[:action]
    assert_empty @project.reporting_credit_policies

    sync(adapter, record)
    policy = @project.reporting_credit_policies.reload.first!
    assert_equal [@tracker.id, "Support", 12.5, Date.new(2026, 4, 1), true],
                 [policy.tracker_id, policy.name, policy.initial_credit_days.to_f, policy.active_from, policy.enabled]
    assert_equal [[4, 1, 2.5, nil], [10, 1, 3.0, Date.new(2026, 1, 1)]],
                 policy.sorted_refills.map { |item| [item.month, item.day, item.credit_days.to_f, item.starts_on] }
    # Refill order in the source response does not matter.
    record["refills"].reverse!
    assert_equal "unchanged", sync(adapter, record)[:action]

    record["refills"] = [refill(7, 1, 5)]
    record["enabled"] = false
    assert_equal "update", sync(adapter, record)[:action]
    policy.reload
    assert_equal [[7, 1]], policy.sorted_refills.map { |item| [item.month, item.day] }
    refute policy.enabled

    policy.reporting_credit_refills.first.update!(credit_days: 9)
    error = assert_raises(RedmineMirror::Error) { sync(adapter, record.merge("name" => "Renamed")) }
    assert_match(/Local modification/, error.message)
    assert_equal "Support", policy.reload.name
  end

  def test_credit_policy_for_a_tracker_already_covered_locally_is_a_conflict
    adapter = RedmineReporting::MirrorAdapters::CreditPolicies.new
    @project.reporting_credit_policies.create!(tracker: @tracker, name: "Local", initial_credit_days: 1,
                                               anniversary_month: 1, anniversary_day: 1)
    error = assert_raises(RedmineMirror::Error) { sync(adapter, policy_record) }
    assert_match(/Existing local/, error.message)
    assert_equal ["Local"], @project.reporting_credit_policies.map(&:name)
  end

  def test_credit_policies_are_read_page_by_page
    pages = [[policy_record(id: 1)], [policy_record(id: 2)]]
    requests = []
    source = Source.new("projects/7/reporting/credit_policies.json" => lambda do |params|
      requests << params.fetch("offset")
      {"reporting_credit_policies" => pages.fetch(requests.size - 1), "total_count" => 2}
    end)
    assert_equal [1, 2], RedmineReporting::MirrorAdapters::CreditPolicies.new.records(source, 7).map { |item| item.fetch("id") }
    assert_equal [0, 1], requests
  end

  private

  def sync(adapter, record, apply: true)
    adapter.synchronize(record, project_id: @project.id, mappings: @mappings, lookup: ->(*) {},
                        store: @store, source: nil, apply: apply)
  end

  def settings_record(hours_per_day: 8.0, section_ids: %w[run], run: [], build: [])
    {"id" => 3, "project" => {"id" => 7}, "hours_per_day" => hours_per_day, "section_ids" => section_ids,
     "run_trackers" => run.map { |id| {"id" => id, "name" => "Tracker #{id}"} },
     "build_trackers" => build.map { |id| {"id" => id, "name" => "Tracker #{id}"} }}
  end

  def policy_record(id: 5, refills: [])
    {"id" => id, "project" => {"id" => 7}, "tracker" => {"id" => 10, "name" => "Support"}, "name" => "Support",
     "initial_credit_days" => 12.5, "anniversary_month" => 4, "anniversary_day" => 1, "active_from" => "2026-04-01",
     "active_until" => nil, "enabled" => true, "refills" => refills}
  end

  def refill(month, day, credit_days, starts_on = nil)
    {"id" => month, "month" => month, "day" => day, "credit_days" => credit_days, "starts_on" => starts_on, "ends_on" => nil}
  end
end
