# frozen_string_literal: true
# File: redmine_reporting/test/integration/sla_coexistence_test.rb
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
  class ReportingSlaCoexistenceTest < ActionDispatch::IntegrationTest
    include ReportingTestData

    def test_real_sla_models_and_reporting_load_together_without_enabling_future_reports
      @project.enable_module!(:sla)
      sla = Sla.create!(name: "Reporting coexistence")
      SlaProjectTracker.create!(project: @project, tracker: @tracker, sla: sla)
      source = RedmineReporting::SlaSource.new(@project)
      assert source.installed?
      assert source.configured?
      assert_equal({}, source.active_statuses_by_type)
      assert_equal IssueStatus.where(is_closed: false).sorted.ids, source.waiting_status_ids
      session = authenticated_session(@administrator)
      session.get "/projects/#{@project.identifier}/settings/reporting"
      assert_equal 200, session.response.status
      assert_includes session.response.body, "reporting-sla-statuses"
      session.get "/projects/#{@project.identifier}/reporting"
      assert_equal 200, session.response.status
      refute_includes session.response.body, 'id="tab-sla"'
    end
  end
end
