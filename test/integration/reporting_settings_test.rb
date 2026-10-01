# frozen_string_literal: true

require_relative "../test_helper"

class ReportingSettingsTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def test_settings_tab_requires_the_manage_permission
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/settings/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML5(session.response.body)
    assert page.at_css("#tab-reporting"), "reporting tab"
    assert page.at_css("form#reporting-settings input#reporting_section_run[checked]")
    assert page.at_css("input#reporting_section_sla[disabled]"), "planned families cannot be enabled"
    # SLA statuses come from the SLA plugin only; nothing is entered here without it.
    refute page.at_css("table.reporting-sla-statuses")
    refute page.at_css("input[name*='waiting_status']")
    refute_includes session.response.body, "translation missing"

    viewer = create_viewer
    viewer_session = authenticated_session(viewer)
    viewer_session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {hours_per_day: 4}}
    assert_equal 403, viewer_session.response.status
    viewer_session.get "/projects/#{@project.identifier}/reporting/credit_policies/new"
    assert_equal 403, viewer_session.response.status
  end

  def test_saving_settings_changes_the_dashboard
    session = authenticated_session(@administrator)
    @child_issue.update_columns(estimated_hours: 10)
    session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {
      hours_per_day: "4", section_ids: ["", "run"],
      tracker_roles: {@tracker.id.to_s => "run", "999999" => "build"}
    }}
    assert_redirected_to_settings session
    setting = ReportingProjectSetting.find_by!(project: @project)
    assert_equal 4, setting.hours_per_day
    assert_equal [@tracker.id], setting.run_tracker_ids
    # Trackers outside the project are ignored.
    assert_empty setting.build_tracker_ids

    session.get "/projects/#{@project.identifier}/reporting"
    summary = JSON.parse(Nokogiri::HTML5(session.response.body).at_css("#report-data").text).fetch("summary")
    # 10 h estimated minus the child's 2 h spent, at 4 h per day.
    assert_equal 2.0, summary.fetch("remainingDays")

    session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {section_ids: [""]}}
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML5(session.response.body)
    refute page.at_css("#report-data")
    assert page.at_css("a[href='/projects/#{@project.identifier}/settings/reporting']")
  end

  def test_tabs_and_cards_follow_the_issue_and_time_tracking_modules
    session = authenticated_session(@administrator)
    enable_modules %w[issue_tracking reporting]
    page = dashboard(session, tab: "activity")
    assert_equal %w[tab-flow tab-backlog tab-performance], page.css(".reporting-tabs a").map { |link| link["id"] }
    # A tab that is not available falls back to the first one.
    assert page.at_css("#panel-flow:not([hidden])")
    refute page.at_css("#estimated-remaining"), "time left needs spent time"
    assert page.at_css(".reporting-kpi-group[aria-label='Issues']")
    refute page.at_css(".reporting-kpi-group[aria-label='Time']")

    enable_modules %w[time_tracking reporting]
    page = dashboard(session)
    assert_equal %w[tab-activity tab-consumption], page.css(".reporting-tabs a").map { |link| link["id"] }
    refute page.at_css(".reporting-kpi-group[aria-label='Issues']")
    time_cards = page.css(".reporting-kpi-group[aria-label='Time'] .reporting-stat .label").map(&:text)
    # Without issues, only the time logged over the period is left; credits are the consumption tab's.
    assert_equal ["Time logged over the period"], time_cards

    enable_modules %w[reporting]
    page = dashboard(session)
    refute page.at_css("#report-data")
    assert_includes page.at_css("p.nodata").text, "Issue tracking"
  end

  def test_subproject_saves_its_own_copy_of_the_inherited_settings
    ReportingProjectSetting.create!(project: @project, hours_per_day: 7, run_tracker_ids: [@tracker.id])
    session = authenticated_session(@administrator)
    session.get "/projects/#{@child.identifier}/settings/reporting"
    assert_includes session.response.body, @project.name
    session.patch "/projects/#{@child.identifier}/reporting/settings", params: {reporting_setting: {hours_per_day: "6"}}
    own = ReportingProjectSetting.find_by!(project: @child)
    assert_equal [6, [@tracker.id]], [own.hours_per_day, own.run_tracker_ids]
    assert_equal 7, ReportingProjectSetting.find_by!(project: @project).hours_per_day
  end

  def test_credit_policies_are_managed_from_the_project_settings
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting/credit_policies/new"
    assert_equal 200, session.response.status
    refute_includes session.response.body, "translation missing"
    # Labels come from the plugin's field translations, not humanized column names.
    assert_includes session.response.body, "Initial credit (days)"
    session.post "/projects/#{@project.identifier}/reporting/credit_policies", params: {reporting_credit_policy: {
      tracker_id: @tracker.id, name: "TMA", initial_credit_days: "20", anniversary_month: "1", anniversary_day: "1", enabled: "1",
      reporting_credit_refills_attributes: {"0" => {month: "7", day: "1", credit_days: "5"}, "1" => {month: "", day: "", credit_days: ""}}
    }}
    assert_redirected_to_settings session
    policy = @project.reporting_credit_policies.find_by!(tracker: @tracker)
    assert_equal [5], policy.reporting_credit_refills.map(&:credit_days)

    session.get "/projects/#{@project.identifier}/settings/reporting"
    assert_includes Nokogiri::HTML5(session.response.body).css("table.reporting-credit-policies td").map(&:text), "TMA"

    refill = policy.reporting_credit_refills.first
    session.patch "/projects/#{@project.identifier}/reporting/credit_policies/#{policy.id}", params: {reporting_credit_policy: {
      initial_credit_days: "-1", reporting_credit_refills_attributes: {"0" => {id: refill.id, _destroy: "1"}}
    }}
    assert_equal 422, session.response.status
    assert_equal 20, policy.reload.initial_credit_days
    session.patch "/projects/#{@project.identifier}/reporting/credit_policies/#{policy.id}", params: {reporting_credit_policy: {
      initial_credit_days: "30", reporting_credit_refills_attributes: {"0" => {id: refill.id, _destroy: "1"}}
    }}
    assert_equal [30, []], [policy.reload.initial_credit_days, policy.reporting_credit_refills.to_a]

    # A live policy from another project must remain inaccessible and unchanged.
    viewer = create_viewer
    viewer.members.first.roles.first.update!(permissions: [:view_reporting, :manage_reporting, :view_issues])
    restricted = authenticated_session(viewer)
    foreign = @outside.reporting_credit_policies.create!(tracker: @tracker, name: "Other budget", initial_credit_days: 42,
                                                        anniversary_month: 1, anniversary_day: 1)
    path = "/projects/#{@project.identifier}/reporting/credit_policies/#{foreign.id}"
    restricted.get "#{path}/edit"
    assert_equal 404, restricted.response.status
    restricted.patch path, params: {reporting_credit_policy: {initial_credit_days: 999}}
    assert_equal 404, restricted.response.status
    restricted.delete path
    assert_equal 404, restricted.response.status
    assert_equal 42, foreign.reload.initial_credit_days
    restricted.get "/projects/#{@outside.identifier}/reporting/credit_policies/#{foreign.id}/edit"
    assert_equal 403, restricted.response.status

    session.delete "/projects/#{@project.identifier}/reporting/credit_policies/#{policy.id}"
    refute ReportingCreditPolicy.exists?(policy.id)
  end

  private

  def assert_redirected_to_settings(session)
    assert_equal 302, session.response.status
    assert_equal "/projects/#{@project.identifier}/settings/reporting", URI(session.response.location).path
  end

  # Reloaded first: Redmine caches enabled modules on the project object.
  def enable_modules(names)
    [@project, @child].each { |project| project.reload.enabled_module_names = names }
  end

  def dashboard(session, **params)
    session.get "/projects/#{@project.identifier}/reporting", params: params
    assert_equal 200, session.response.status
    Nokogiri::HTML5(session.response.body)
  end
end
