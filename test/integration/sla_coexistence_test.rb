# frozen_string_literal: true
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
