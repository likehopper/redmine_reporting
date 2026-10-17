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

  def test_credit_policies_are_listed_with_their_refills_and_paginated
    policy = @project.reporting_credit_policies.create!(tracker: @tracker, name: "Support", initial_credit_days: 12.5,
      anniversary_month: 4, anniversary_day: 1, active_from: Date.new(2026, 4, 1), enabled: true,
      reporting_credit_refills_attributes: [{month: 10, day: 1, credit_days: 3, starts_on: Date.new(2026, 1, 1)}])
    second_tracker = Tracker.where.not(id: @tracker.id).first!
    @project.trackers << second_tracker
    @project.reporting_credit_policies.create!(tracker: second_tracker, name: "Bugs", initial_credit_days: 2,
      anniversary_month: 1, anniversary_day: 1, enabled: false)
    @outside.reporting_credit_policies.create!(tracker: @tracker, name: "Elsewhere", initial_credit_days: 1,
      anniversary_month: 1, anniversary_day: 1)

    get "/projects/#{@project.identifier}/reporting/credit_policies.json", params: {limit: 1}, headers: @key
    assert_response :success
    body = response.parsed_body
    assert_equal [2, 0, 1], body.values_at("total_count", "offset", "limit")
    assert_equal 1, body.fetch("reporting_credit_policies").size
    listed = body.fetch("reporting_credit_policies").first
    assert_equal policy.id, listed.fetch("id")
    assert_equal({"id" => @tracker.id, "name" => @tracker.name}, listed.fetch("tracker"))
    assert_equal [12.5, 4, 1, "2026-04-01", nil, true],
                 listed.values_at("initial_credit_days", "anniversary_month", "anniversary_day", "active_from", "active_until", "enabled")
    assert_equal [[10, 1, 3.0, "2026-01-01", nil]],
                 listed.fetch("refills").map { |refill| refill.values_at("month", "day", "credit_days", "starts_on", "ends_on") }

    get "/projects/#{@project.identifier}/reporting/credit_policies.json", params: {offset: 1}, headers: @key
    assert_equal ["Bugs"], response.parsed_body.fetch("reporting_credit_policies").map { |item| item.fetch("name") }

    get "/projects/#{@project.identifier}/reporting/credit_policies/#{policy.id}.json", headers: @key
    assert_equal "Support", response.parsed_body.fetch("reporting_credit_policy").fetch("name")
    # Another project's policy is not reachable through this project.
    get "/projects/#{@outside.identifier}/reporting/credit_policies/#{policy.id}.json", headers: @key
    assert_response :not_found
  end

  # Contract with the Redmine Mirror adapters: they consume these exact responses.
  def test_mirror_copies_the_configuration_read_through_this_api
    skip "Redmine Mirror is not installed" unless Redmine::Plugin.installed?(:redmine_mirror)
    ReportingProjectSetting.update_for(@project, hours_per_day: 7, section_ids: %w[run workload],
                                                 tracker_roles: {@tracker.id.to_s => "run"})
    @project.reporting_credit_policies.create!(tracker: @tracker, name: "Support", initial_credit_days: 10,
      anniversary_month: 1, anniversary_day: 1, reporting_credit_refills_attributes: [{month: 7, day: 1, credit_days: 2}])
    source = api_client
    adapters = %w[reporting_settings reporting_credit_policies].map { |key| RedmineMirror::REGISTRY[key] }
    catalog = RedmineMirror::SourceCatalog.new(client: source, project_id: @project.id, adapters: adapters).fetch
    assert_equal @tracker.name, catalog.fetch("tracker").fetch(@tracker.id.to_s)

    store = RedmineMirror::DatabaseStore.new("reporting-api-contract", project_id: @outside.id)
    mappings = {"tracker" => {@tracker.id.to_s => @tracker.id.to_s}}
    adapters.each do |adapter|
      records = adapter.records(source, @project.id).to_a
      assert_equal 1, records.size, adapter.key
      event = adapter.synchronize(records.first, project_id: @outside.id, mappings: mappings, lookup: ->(*) {},
                                  store: store, source: source, apply: true)
      assert_equal "create", event[:action], adapter.key
    end
    copied = ReportingProjectSetting.find_by!(project: @outside)
    assert_equal [7.0, %w[run workload], [@tracker.id]], [copied.hours_per_day.to_f, copied.section_ids, copied.run_tracker_ids]
    policy = @outside.reporting_credit_policies.first!
    assert_equal ["Support", [[7, 1, 2.0]]], [policy.name, policy.sorted_refills.map { |refill| [refill.month, refill.day, refill.credit_days.to_f] }]
  end

  def test_reading_the_configuration_requires_the_manage_permission
    viewer = create_viewer
    get "/projects/#{@project.identifier}/reporting/credit_policies.json", headers: {"X-Redmine-API-Key" => viewer.api_key}
    assert_response :forbidden
    get "/projects/#{@project.identifier}/reporting/settings.json", headers: {"X-Redmine-API-Key" => viewer.api_key}
    assert_response :forbidden
    get "/projects/#{@project.identifier}/reporting/settings.json"
    assert_response :unauthorized

    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting/credit_policies"
    assert_equal "/projects/#{@project.identifier}/settings/reporting", URI(session.response.location).path
  end
end
