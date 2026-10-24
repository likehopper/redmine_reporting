# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_api_test.rb
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

# Read-only REST API used by Redmine Mirror and other tools to copy a project's reporting configuration.
class ReportingApiTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def setup
    Setting.rest_api_enabled = "1"
    @key = {"X-Redmine-API-Key" => @administrator.api_key}
  end

  # Mirror's source client interface, served by this application.
  def api_client
    test = self
    Object.new.tap do |client|
      client.define_singleton_method(:get) do |path, params = {}|
        test.get("/#{path}", params: params, headers: test.instance_variable_get(:@key))
        test.assert_response :success
        test.response.parsed_body
      end
    end
  end

  def teardown
    Setting.rest_api_enabled = "0"
  end

  def test_settings_report_own_inherited_and_default_configuration
    get "/projects/#{@project.identifier}/reporting/settings.json", headers: @key
    assert_response :success
    setting = response.parsed_body.fetch("reporting_setting")
    assert_nil setting["id"]
    assert_equal ["run"], setting.fetch("section_ids")
    assert_equal 8.0, setting.fetch("hours_per_day")

    own = ReportingProjectSetting.update_for(@project, hours_per_day: 4, section_ids: %w[run build],
                                                       tracker_roles: {@tracker.id.to_s => "build"})
    get "/projects/#{@project.identifier}/reporting/settings.json", headers: @key
    setting = response.parsed_body.fetch("reporting_setting")
    assert_equal own.id, setting.fetch("id")
    assert_equal({"id" => @project.id, "name" => @project.name}, setting.fetch("project"))
    refute setting.key?("inherited_from")
    assert_equal 4.0, setting.fetch("hours_per_day")
    assert_equal %w[run build], setting.fetch("section_ids")
    assert_empty setting.fetch("run_trackers")
    assert_equal [{"id" => @tracker.id, "name" => @tracker.name}], setting.fetch("build_trackers")

    get "/projects/#{@child.identifier}/reporting/settings.json", headers: @key
    setting = response.parsed_body.fetch("reporting_setting")
    assert_equal own.id, setting.fetch("id")
    assert_equal @child.id, setting.fetch("project").fetch("id")
    assert_equal @project.id, setting.fetch("inherited_from").fetch("id")
  end

  def test_contracts_are_listed_with_their_envelopes_and_paginated
    activity = TimeEntryActivity.shared.active.first!
    contract = @project.reporting_credit_contracts.create!(name: "Support", starts_on: Date.new(2026, 4, 1), ends_on: Date.new(2027, 3, 31),
      tracker_ids: [@tracker.id], include_subprojects: true, envelopes_attributes: [
        {name: "Development", days: 12.5, activity_ids: [activity.id], issue_privacy: "public",
         movements_attributes: [{date: Date.new(2026, 10, 1), days: 3, comment: "Amendment"}]}
      ])
    @project.reporting_credit_contracts.create!(name: "Bugs", starts_on: Date.new(2027, 4, 1), ends_on: Date.new(2027, 6, 30),
      tracker_ids: [@tracker.id], envelopes_attributes: [{name: "All", days: 2, other_activities: true}])
    @outside.reporting_credit_contracts.create!(name: "Elsewhere", starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 12, 31),
      tracker_ids: [@tracker.id], envelopes_attributes: [{name: "All", days: 1, other_activities: true}])

    get "/projects/#{@project.identifier}/reporting/credit_contracts.json", params: {limit: 1}, headers: @key
    assert_response :success
    body = response.parsed_body
    assert_equal [2, 0, 1], body.values_at("total_count", "offset", "limit")
    listed = body.fetch("reporting_credit_contracts").first
    assert_equal [contract.id, "2026-04-01", "2027-03-31", true], listed.values_at("id", "starts_on", "ends_on", "include_subprojects")
    assert_equal [{"id" => @tracker.id, "name" => @tracker.name}], listed.fetch("trackers")
    envelope = listed.fetch("envelopes").first
    assert_equal ["Development", 12.5, false, "public", [{"id" => activity.id, "name" => activity.name}]],
                 envelope.values_at("name", "days", "other_activities", "issue_privacy", "activities")
    assert_equal [["2026-10-01", 3.0, "Amendment", nil]],
                 envelope.fetch("movements").map { |movement| movement.values_at("date", "days", "comment", "source_envelope_id") }

    get "/projects/#{@project.identifier}/reporting/credit_contracts.json", params: {offset: 1}, headers: @key
    assert_equal ["Bugs"], response.parsed_body.fetch("reporting_credit_contracts").map { |item| item.fetch("name") }

    get "/projects/#{@project.identifier}/reporting/credit_contracts/#{contract.id}.json", headers: @key
    assert_equal "Support", response.parsed_body.fetch("reporting_credit_contract").fetch("name")
    # Another project's contract is not reachable through this project.
    get "/projects/#{@outside.identifier}/reporting/credit_contracts/#{contract.id}.json", headers: @key
    assert_response :not_found
  end

  # Contract with the Redmine Mirror adapters: they consume these exact responses.
  def test_mirror_copies_the_configuration_read_through_this_api
    skip "Redmine Mirror is not installed" unless Redmine::Plugin.installed?(:redmine_mirror)
    ReportingProjectSetting.update_for(@project, hours_per_day: 7, section_ids: %w[run workload],
                                                 tracker_roles: {@tracker.id.to_s => "run"})
    activity = TimeEntryActivity.shared.active.first!
    @project.reporting_credit_contracts.create!(name: "Support", starts_on: Date.new(2026, 1, 1), ends_on: Date.new(2026, 12, 31),
      tracker_ids: [@tracker.id], envelopes_attributes: [{name: "Dev", days: 10, activity_ids: [activity.id],
                                                         movements_attributes: [{date: Date.new(2026, 7, 1), days: 2}]}])
    source = api_client
    adapters = %w[reporting_settings reporting_credit_contracts].map { |key| RedmineMirror::REGISTRY[key] }
    catalog = RedmineMirror::SourceCatalog.new(client: source, project_id: @project.id, adapters: adapters).fetch
    assert_equal @tracker.name, catalog.fetch("tracker").fetch(@tracker.id.to_s)

    store = RedmineMirror::DatabaseStore.new("reporting-api-contract", project_id: @outside.id)
    mappings = {"tracker" => {@tracker.id.to_s => @tracker.id.to_s}, "activity" => {activity.id.to_s => activity.id.to_s}}
    adapters.each do |adapter|
      records = adapter.records(source, @project.id).to_a
      assert_equal 1, records.size, adapter.key
      event = adapter.synchronize(records.first, project_id: @outside.id, mappings: mappings, lookup: ->(*) {},
                                  store: store, source: source, apply: true)
      assert_equal "create", event[:action], adapter.key
    end
    copied = ReportingProjectSetting.find_by!(project: @outside)
    assert_equal [7.0, %w[run workload], [@tracker.id]], [copied.hours_per_day.to_f, copied.section_ids, copied.run_tracker_ids]
    contract = @outside.reporting_credit_contracts.first!
    assert_equal ["Support", [activity.id], [2.0]],
                 [contract.name, contract.envelopes.first.activity_ids, contract.envelopes.first.movements.map { |movement| movement.days.to_f }]
  end

  def test_reading_the_configuration_requires_the_manage_permission
    viewer = create_viewer
    get "/projects/#{@project.identifier}/reporting/credit_contracts.json", headers: {"X-Redmine-API-Key" => viewer.api_key}
    assert_response :forbidden
    get "/projects/#{@project.identifier}/reporting/settings.json", headers: {"X-Redmine-API-Key" => viewer.api_key}
    assert_response :forbidden
    get "/projects/#{@project.identifier}/reporting/settings.json"
    assert_response :unauthorized

    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting/credit_contracts"
    assert_equal "/projects/#{@project.identifier}/settings/reporting", URI(session.response.location).path
  end
end
