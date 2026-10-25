# frozen_string_literal: true
# File: redmine_reporting/test/integration/reporting_settings_test.rb
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

class ReportingSettingsTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def test_settings_tab_requires_the_manage_permission
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/settings/reporting"
    assert_equal 200, session.response.status
    page = Nokogiri::HTML5(session.response.body)
    assert page.at_css("#tab-reporting"), "reporting tab"
    # SLA statuses come from the SLA plugin only; their pane is hidden without it.
    assert_equal %w[sections time_unit trackers contracts],
                 page.css(".reporting-settings-nav a").map { |link| link["id"].delete_prefix("reporting-pane-") }
    assert page.at_css(".reporting-settings-nav a#reporting-pane-sections.selected[aria-current='page']")
    assert page.at_css("form.reporting-settings-form input#reporting_section_run[checked]")
    assert page.at_css("input#reporting_section_sla[disabled]"), "planned families cannot be enabled"
    # One pane at a time: the other settings are not part of this form.
    refute page.at_css("#reporting_setting_hours_per_day")
    refute page.at_css("a[href$='/reporting/credit_contracts/new']")
    refute_includes session.response.body, "translation missing"

    { "time_unit" => "#reporting_setting_hours_per_day", "trackers" => "table.reporting-tracker-roles",
      "contracts" => "a[href$='/reporting/credit_contracts/new']", "sla_statuses" => "#reporting_section_run" }.each do |pane, selector|
      session.get "/projects/#{@project.identifier}/settings/reporting", params: {reporting_pane: pane}
      page = Nokogiri::HTML5(session.response.body)
      # An unavailable pane falls back to the first one.
      selected = pane == "sla_statuses" ? "sections" : pane
      assert page.at_css("a#reporting-pane-#{selected}.selected"), pane
      assert page.at_css(selector), pane
      refute page.at_css("table.reporting-sla-statuses"), pane
      refute_includes session.response.body, "translation missing"
    end

    viewer = create_viewer
    viewer_session = authenticated_session(viewer)
    viewer_session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {hours_per_day: 4}}
    assert_equal 403, viewer_session.response.status
    viewer_session.get "/projects/#{@project.identifier}/reporting/credit_contracts/new"
    assert_equal 403, viewer_session.response.status
    # The help page only needs the permission to view reporting.
    viewer_session.get "/projects/#{@project.identifier}/reporting/help"
    assert_equal 200, viewer_session.response.status
    assert Nokogiri::HTML5(viewer_session.response.body).at_css(".reporting-help h3#envelopes")
  end

  def test_saving_settings_changes_the_dashboard
    session = authenticated_session(@administrator)
    @child_issue.update_columns(estimated_hours: 10)
    session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {
      hours_per_day: "4", section_ids: ["", "run"],
      tracker_roles: {@tracker.id.to_s => "run", "999999" => "build"}
    }, reporting_pane: "trackers"}
    assert_redirected_to_settings session, pane: "trackers"
    setting = ReportingProjectSetting.find_by!(project: @project)
    assert_equal 4, setting.hours_per_day
    assert_equal [@tracker.id], setting.run_tracker_ids
    # Trackers outside the project are ignored.
    assert_empty setting.build_tracker_ids

    session.get "/projects/#{@project.identifier}/reporting"
    summary = JSON.parse(Nokogiri::HTML5(session.response.body).at_css("#report-data").text).fetch("summary")
    # 10 h estimated minus the child's 2 h spent, at 4 h per day.
    assert_equal 2.0, summary.fetch("remainingDays")

    # Saving one pane leaves the others' values alone.
    session.patch "/projects/#{@project.identifier}/reporting/settings", params: {reporting_setting: {section_ids: [""]}, reporting_pane: "bogus"}
    assert_redirected_to_settings session
    assert_equal [4, [@tracker.id]], setting.reload.then { |saved| [saved.hours_per_day, saved.run_tracker_ids] }
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

  def test_contracts_are_managed_from_the_project_settings
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting/credit_contracts/new"
    assert_equal 200, session.response.status
    refute_includes session.response.body, "translation missing"
    page = Nokogiri::HTML5(session.response.body)
    # A new contract is prefilled with one envelope for all activities.
    assert_equal "All activities", page.at_css("#reporting_credit_contract_envelopes_attributes_0_name")["value"]
    assert page.at_css("#reporting_credit_contract_envelopes_attributes_0_other_activities[checked]")
    assert page.at_css("a.reporting-help-link[href$='/reporting/help#envelopes']")

    development = TimeEntryActivity.shared.active.first!
    session.post "/projects/#{@project.identifier}/reporting/credit_contracts", params: {reporting_credit_contract: {
      name: "TMA 2027", starts_on: "2027-01-01", ends_on: "2027-12-31", tracker_ids: ["", @tracker.id.to_s, "999999"],
      envelopes_attributes: {
        "0" => {name: "Development", days: "20", other_activities: "0", issue_privacy: "public", activity_ids: ["", development.id.to_s],
                movements_attributes: {"0" => {date: "2027-06-01", days: "5", comment: "Amendment"}, "1" => {date: "", days: "", comment: ""}}},
        "1" => {name: "", days: ""}
      }
    }}
    assert_redirected_to_settings session, pane: "contracts"
    contract = @project.reporting_credit_contracts.find_by!(name: "TMA 2027")
    # Trackers outside the project are ignored; the blank envelope and movement rows too.
    assert_equal [[@tracker.id], 1], [contract.tracker_ids, contract.envelopes.count]
    assert_equal [[development.id], [5]], [contract.envelopes.first.activity_ids, contract.envelopes.first.movements.map(&:days)]

    session.get "/projects/#{@project.identifier}/settings/reporting", params: {reporting_pane: "contracts"}
    page = Nokogiri::HTML5(session.response.body)
    assert_includes page.css("#reporting-contracts-upcoming td.name").map(&:text), "TMA 2027"
    refute_includes session.response.body, "translation missing"

    envelope = contract.envelopes.first
    session.patch "/projects/#{@project.identifier}/reporting/credit_contracts/#{contract.id}", params: {reporting_credit_contract: {
      ends_on: "2026-12-31"
    }}
    assert_equal 422, session.response.status
    assert_equal Date.new(2027, 12, 31), contract.reload.ends_on
    session.patch "/projects/#{@project.identifier}/reporting/credit_contracts/#{contract.id}", params: {reporting_credit_contract: {
      envelopes_attributes: {"0" => {id: envelope.id, days: "30", movements_attributes: {"0" => {id: envelope.movements.first.id, _destroy: "1"}}}}
    }}
    assert_redirected_to_settings session, pane: "contracts"
    assert_equal [30, []], [envelope.reload.days, envelope.movements.to_a]

    # Renewing offers to carry the balance over; the days come from the server, not the form.
    User.current = @administrator
    TimeEntry.create!(project: @project, issue: @parent_issue, user: @administrator, activity: development, hours: 8, spent_on: Date.new(2027, 3, 1))
    session.get "/projects/#{@project.identifier}/reporting/credit_contracts/#{contract.id}/renew"
    page = Nokogiri::HTML5(session.response.body)
    assert_equal ["2028-01-01", "2028-12-31"], %w[starts_on ends_on].map { |field| page.at_css("#reporting_credit_contract_#{field}")["value"] }
    assert_includes page.text, "Carry over the 29d left"
    refute_includes page.text, "Inactive Activity"
    session.post "/projects/#{@project.identifier}/reporting/credit_contracts", params: {reporting_credit_contract: {
      name: "TMA 2028", starts_on: "2028-01-01", ends_on: "2028-12-31", tracker_ids: [@tracker.id.to_s],
      envelopes_attributes: {"0" => {name: "Development", days: "20", issue_privacy: "public", activity_ids: [development.id.to_s],
                                     carry_source_id: envelope.id.to_s, carry: "1", movements_attributes: {"0" => {date: "2028-02-01", days: "999"}}}}
    }}
    assert_redirected_to_settings session, pane: "contracts"
    renewal = @project.reporting_credit_contracts.find_by!(name: "TMA 2028").envelopes.first
    carried = renewal.movements.find_by!(source_envelope_id: envelope.id)
    assert_equal [Date.new(2028, 1, 1), 29, "Carried over from TMA 2027 (Development)"], [carried.date, carried.days, carried.comment]

    # A contract from another project must remain inaccessible and unchanged.
    viewer = create_viewer
    viewer.members.first.roles.first.update!(permissions: [:view_reporting, :manage_reporting, :view_issues])
    restricted = authenticated_session(viewer)
    foreign = @outside.reporting_credit_contracts.create!(name: "Other budget", starts_on: Date.new(2027, 1, 1), ends_on: Date.new(2027, 12, 31),
                                                        tracker_ids: [@tracker.id], envelopes_attributes: [{name: "All", days: 42, other_activities: true}])
    path = "/projects/#{@project.identifier}/reporting/credit_contracts/#{foreign.id}"
    restricted.get "#{path}/edit"
    assert_equal 404, restricted.response.status
    restricted.get "#{path}/renew"
    assert_equal 404, restricted.response.status
    restricted.patch path, params: {reporting_credit_contract: {name: "Changed"}}
    assert_equal 404, restricted.response.status
    restricted.delete path
    assert_equal 404, restricted.response.status
    assert_equal "Other budget", foreign.reload.name
    # Nor can its balance be carried into this project.
    restricted.post "/projects/#{@project.identifier}/reporting/credit_contracts", params: {reporting_credit_contract: {
      name: "Stolen", starts_on: "2029-01-01", ends_on: "2029-12-31", tracker_ids: [@tracker.id.to_s],
      envelopes_attributes: {"0" => {name: "All", days: "1", other_activities: "1", carry_source_id: foreign.envelopes.first.id.to_s, carry: "1"}}
    }}
    assert_empty @project.reporting_credit_contracts.find_by!(name: "Stolen").envelopes.first.movements
    restricted.get "/projects/#{@outside.identifier}/reporting/credit_contracts/#{foreign.id}/edit"
    assert_equal 403, restricted.response.status

    session.delete "/projects/#{@project.identifier}/reporting/credit_contracts/#{contract.id}"
    refute ReportingCreditContract.exists?(contract.id)
    assert_nil carried.reload.source_envelope_id
  end

  private

  def assert_redirected_to_settings(session, pane: nil)
    assert_equal 302, session.response.status
    location = URI(session.response.location)
    assert_equal "/projects/#{@project.identifier}/settings/reporting", location.path
    selected = Rack::Utils.parse_query(location.query.to_s)["reporting_pane"]
    pane ? assert_equal(pane, selected) : assert_nil(selected)
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
