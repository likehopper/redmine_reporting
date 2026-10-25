# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_sla_test.rb
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

if Redmine::Plugin.installed?(:redmine_sla)
  # SLA report over a real SLA configuration (see ReportingSlaData).
  class ReportingSlaTest < ActionDispatch::IntegrationTest
    include ReportingTestData
    include ReportingSlaData

    setup :prepare_sla_data

    def test_delays_count_in_the_period_they_ended_and_running_ones_only_today
      response = report(from: @today - 10, to: @today).find { |type| type["id"] == @response.id }
      assert_equal 2, response["ended"]
      assert_equal 1, response["respected"]
      assert_in_delta 50.0, response["rate"]
      assert_equal [0, 1, 0, 1], response["distribution"]
      assert_equal 2, response["periodEnded"].sum
      assert_in_delta 0.5, response["periodExcessHours"].compact.sum
      assert_equal({"late" => 1, "warning" => 0, "on_time" => 0}, response["running"])
      assert_equal [["priority:#{@priority.id}", @priority.name, 2]], response["pivots"].map { |pivot| pivot.values_at("key", "label", "ended") }

      resolution = report(from: @today - 10, to: @today).find { |type| type["id"] == @resolution.id }
      assert_equal 0, resolution["ended"], "no time used for this type in the SLA cache"

      past = report(from: @today - 60, to: @today - 20).find { |type| type["id"] == @response.id }
      assert_equal 1, past["ended"]
      assert_nil past["running"], "running delays are only known today"
    end

    def test_clicks_open_the_issues_counted_by_the_report
      ended = {sla_type: @response.id, sla_end_from: @today - 10, sla_end_to: @today}
      assert_equal [@respected.id, @overrun.id], listed(**ended)
      assert_equal [@respected.id], listed(**ended, sla_buckets: RedmineReporting::SlaFigures::RESPECTED.join(","))
      assert_equal [@overrun.id], listed(**ended, sla_buckets: "gt100")
      assert_equal [@respected.id, @overrun.id], listed(**ended, sla_pivot: "priority:#{@priority.id}")
      assert_equal [@running.id], listed(sla_type: @response.id, sla_running: "true", sla_buckets: "gt100")
      assert_equal [], listed(sla_type: 0)
    end

    def test_the_tab_needs_the_permission_to_view_sla_data
      viewer = create_viewer
      session = authenticated_session(viewer)
      session.get "/projects/#{@project.identifier}/reporting", params: {section: "sla"}
      refute_includes session.response.body, 'id="tab-sla"'
      refute_includes session.response.body, "section=sla"
      Role.find_by!(name: "Reporting query viewer").add_permission!(:view_sla)
      session.get "/projects/#{@project.identifier}/reporting", params: {section: "sla"}
      assert_includes session.response.body, 'id="tab-sla"'
    end

    private

    def report(**parameters)
      session = authenticated_session(@administrator)
      session.get "/projects/#{@project.identifier}/reporting", params: {section: "sla", **parameters}
      assert_equal 200, session.response.status
      refute_match(/translation missing/i, session.response.body)
      JSON.parse(Nokogiri::HTML(session.response.body).at_css("#report-data").text).fetch("sla").fetch("types")
    end

    def listed(**selection)
      session = authenticated_session(@administrator)
      session.get "/projects/#{@project.identifier}/reporting/details",
        params: {section: "sla", records: "issues", from: @today - 10, to: @today, **selection}
      assert_equal 302, session.response.status
      session.follow_redirect!
      assert_equal 200, session.response.status
      Nokogiri::HTML(session.response.body).css("tr.issue").map { |row| row["id"].delete_prefix("issue-").to_i }
    end
  end
end
