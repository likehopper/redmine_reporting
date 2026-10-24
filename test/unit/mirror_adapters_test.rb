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
    @activity = TimeEntryActivity.shared.active.first!
    @mappings = {"tracker" => {"10" => @tracker.id.to_s, "20" => @second_tracker.id.to_s, "30" => "ignore"},
                 "activity" => {"9" => @activity.id.to_s, "11" => "ignore"}}
  end

  def test_adapters_follow_the_mirror_contract
    %w[reporting_settings reporting_credit_contracts].each do |key|
      adapter = RedmineMirror::REGISTRY[key]
      assert_kind_of RedmineReporting::MirrorAdapters::Base, adapter
      assert adapter.available?
      assert_equal "Reporting settings", I18n.t(adapter.label, locale: :en) if key == "reporting_settings"
    end
    # init.rb runs again after a code reload; registering twice is harmless.
    RedmineReporting::MirrorAdapters.register
    setting = MirrorProjectSetting.new(project: @project, source_url: "https://source.example", source_project_id: 7)
    assert_equal "/projects/#{@project.identifier}/reporting/credit_contracts/3/edit",
                 RedmineMirror::REGISTRY["reporting_credit_contracts"].local_path(3, @project)
    assert_equal %w[tracker activity], RedmineMirror::REGISTRY["reporting_credit_contracts"].mapping_tables.map(&:key)
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

  def test_contracts_import_with_envelopes_and_movements_and_detect_local_changes
    adapter = RedmineReporting::MirrorAdapters::CreditContracts.new
    record = contract_record(movements: [movement("2026-10-01", 3), movement("2026-04-01", -2.5)])

    assert_equal "create", sync(adapter, record, apply: false)[:action]
    assert_empty @project.reporting_credit_contracts

    sync(adapter, record)
    contract = @project.reporting_credit_contracts.reload.first!
    # The ignored tracker and activity are left out.
    assert_equal ["TMA", [@tracker.id], Date.new(2026, 1, 1), true], [contract.name, contract.tracker_ids, contract.starts_on, contract.include_subprojects]
    envelope = contract.envelopes.first
    assert_equal ["Development", 12.5, [@activity.id], "public"], [envelope.name, envelope.days.to_f, envelope.activity_ids, envelope.issue_privacy]
    assert_equal [[Date.new(2026, 4, 1), -2.5], [Date.new(2026, 10, 1), 3.0]], envelope.movements.map { |item| [item.date, item.days.to_f] }
    # Movement order in the source response does not matter.
    record["envelopes"].first["movements"].reverse!
    assert_equal "unchanged", sync(adapter, record)[:action]

    record["envelopes"].first["movements"] = [movement("2026-07-01", 5)]
    record["ends_on"] = "2026-09-30"
    assert_equal "update", sync(adapter, record)[:action]
    contract.reload
    assert_equal [Date.new(2026, 9, 30), [Date.new(2026, 7, 1)]], [contract.ends_on, contract.envelopes.first.movements.map(&:date)]

    contract.envelopes.first.update!(days: 9)
    error = assert_raises(RedmineMirror::Error) { sync(adapter, record.merge("name" => "Renamed")) }
    assert_match(/Local modification/, error.message)
    assert_equal "TMA", contract.reload.name
  end

  def test_a_contract_with_only_ignored_trackers_is_ignored
    adapter = RedmineReporting::MirrorAdapters::CreditContracts.new
    record = contract_record
    assert_nil adapter.ignored_reference(record, @mappings)
    record["trackers"] = [{"id" => 30, "name" => "Ignored"}]
    assert_equal "tracker", adapter.ignored_reference(record, @mappings)
    assert_equal({"tracker" => [30], "activity" => [9, 11]}, adapter.used_references(record))
  end

  def test_a_contract_made_locally_with_the_same_name_and_start_is_a_conflict
    adapter = RedmineReporting::MirrorAdapters::CreditContracts.new
    @project.reporting_credit_contracts.create!(name: "TMA", starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 3, 31),
                                                tracker_ids: [@second_tracker.id], envelopes_attributes: [{name: "All", days: 1, other_activities: true}])
    error = assert_raises(RedmineMirror::Error) { sync(adapter, contract_record) }
    assert_match(/Existing local/, error.message)
    assert_equal [Date.new(2026, 3, 31)], @project.reporting_credit_contracts.map(&:ends_on)
  end

  def test_contracts_are_read_page_by_page
    pages = [[contract_record(id: 1)], [contract_record(id: 2)]]
    requests = []
    source = Source.new("projects/7/reporting/credit_contracts.json" => lambda do |params|
      requests << params.fetch("offset")
      {"reporting_credit_contracts" => pages.fetch(requests.size - 1), "total_count" => 2}
    end)
    assert_equal [1, 2], RedmineReporting::MirrorAdapters::CreditContracts.new.records(source, 7).map { |item| item.fetch("id") }
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

  def contract_record(id: 5, movements: [])
    {"id" => id, "project" => {"id" => 7}, "name" => "TMA", "description" => nil, "starts_on" => "2026-01-01", "ends_on" => "2026-12-31",
     "include_subprojects" => true, "trackers" => [{"id" => 10, "name" => "Support"}, {"id" => 30, "name" => "Ignored"}],
     "envelopes" => [{"id" => 4, "name" => "Development", "days" => 12.5, "other_activities" => false, "issue_privacy" => "public",
                      "position" => 0, "activities" => [{"id" => 9, "name" => "Design"}, {"id" => 11, "name" => "Ignored"}],
                      "movements" => movements}]}
  end

  def movement(date, days)
    {"id" => date.delete("-").to_i, "date" => date, "days" => days, "comment" => "Amendment", "source_envelope_id" => nil}
  end
end
