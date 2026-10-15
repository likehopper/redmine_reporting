# frozen_string_literal: true
# File: redmine_reporting/test/documentation/configuration_test.rb
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

# Walks through doc/CONFIGURATION.md in a browser and regenerates its screenshots.
# Run it alone, on a disposable database holding only Redmine's default data:
# test/documentation/run.sh does so in a throwaway container.
require File.expand_path("../../../../test/application_system_test_case", __dir__)
require Rails.root.join("plugins/redmine_reporting/db/demo_data")

class ReportingConfigurationDocumentationTest < ApplicationSystemTestCase
  # Steps follow the document: each one starts where the previous one left the database.
  i_suck_and_my_tests_are_order_dependent!
  self.use_transactional_tests = false
  # The demo generator refuses databases holding Redmine's test fixtures.
  self.fixture_table_names = []

  SCREENSHOTS = ENV.fetch("REPORTING_DOC_SCREENSHOTS") { Rails.root.join("tmp/redmine_reporting/screenshots").to_s }
  PROJECT = RedmineReporting::DemoData::PROJECT_IDENTIFIER
  ROLES = [RedmineReporting::DemoData::MANAGER_ROLE, RedmineReporting::DemoData::DEVELOPER_ROLE].freeze
  ADMIN_LOGIN = "reporting-doc-admin"
  ADMIN_PASSWORD = "Reporting-doc-123!"

  setup do
    prepare_demo_project unless self.class.instance_variable_get(:@prepared)
    self.class.instance_variable_set(:@prepared, true)
    log_user(ADMIN_LOGIN, ADMIN_PASSWORD)
  end

  def test_01_plugin_is_installed
    visit "/admin/plugins"
    assert_selector "tr#plugin-redmine_reporting"
    screenshot "01-admin-plugins", "#content"
  end

  def test_02_roles_get_reporting_permissions
    role = Role.find_by!(name: RedmineReporting::DemoData::MANAGER_ROLE)
    visit "/roles/#{role.id}/edit"
    fieldset = find("#role_permissions_view_reporting").ancestor("fieldset")
    fieldset.check("role_permissions_view_reporting")
    fieldset.check("role_permissions_manage_reporting")
    screenshot "02-role-permissions", fieldset
    click_button "Save"
    assert_selector "#flash_notice"

    # The developer role only views the dashboard.
    developer = Role.find_by!(name: RedmineReporting::DemoData::DEVELOPER_ROLE)
    visit "/roles/#{developer.id}/edit"
    check "role_permissions_view_reporting"
    click_button "Save"
    assert_selector "#flash_notice"
  end

  def test_03_project_enables_the_module
    visit "/projects/#{PROJECT}/settings/info"
    check "project_enabled_module_names_reporting"
    screenshot "03-project-modules", "#project_modules"
    within("#tab-content-info") { click_button "Save" }
    assert_selector "#flash_notice"
    assert_selector "#main-menu a.redmine-reporting"
    screenshot "04-project-menu", "#main-menu"
  end

  def test_04_settings_tab
    visit "/projects/#{PROJECT}/settings/reporting"
    assert_selector "#reporting-settings"
    screenshot "05-settings-default", "#tab-content-reporting"
    within "#reporting-settings" do
      check "reporting_section_run"
      check "reporting_section_build"
      check "reporting_section_workload"
      fill_in "reporting_setting_hours_per_day", with: "7.5"
      { "Bug" => "run", "Support request" => "run", "Feature request" => "build" }.each do |name, role|
        choose "reporting_tracker_#{Tracker.find_by!(name: name).id}_#{role}"
      end
    end
    screenshot "06-settings-filled", "#reporting-settings"
    within("#reporting-settings") { click_button "Save" }
    assert_selector "#flash_notice"
    assert_equal 7.5, ReportingProjectSetting.find_by!(project: Project.find_by!(identifier: PROJECT)).hours_per_day
  end

  def test_05_time_credit
    visit "/projects/#{PROJECT}/settings/reporting"
    click_link "New credit"
    select "Support request", from: "reporting_credit_policy_tracker_id"
    fill_in "reporting_credit_policy_name", with: "Annual support contract"
    fill_in "reporting_credit_policy_initial_credit_days", with: "20"
    select "1", from: "reporting_credit_policy_anniversary_day"
    select "January", from: "reporting_credit_policy_anniversary_month"
    fill_date "reporting_credit_policy_active_from", Date.current.beginning_of_year
    refill = "reporting_credit_policy[reporting_credit_refills_attributes][0]"
    find("select[name='#{refill}[day]']").select("1")
    find("select[name='#{refill}[month]']").select("July")
    find("input[name='#{refill}[credit_days]']").fill_in(with: "5")
    screenshot "07-credit-form", "#content"
    click_button "Create"
    assert_selector "#flash_notice"
    assert_selector "table.reporting-credit-policies td", text: "Annual support contract"
    screenshot "08-credit-list", find("table.reporting-credit-policies").ancestor("fieldset")
  end

  def test_06_subproject_inherits_settings
    visit "/projects/reporting-demo-maintenance/settings/reporting"
    assert_selector "#reporting-settings p.warning"
    screenshot "09-subproject-inherited", "#reporting-settings"
  end

  def test_07_run_dashboard
    open_reporting(section: "run", tab: "flow")
    screenshot "10-run-flow", "#content"
    %w[activity consumption backlog performance].each_with_index do |tab, index|
      open_reporting(section: "run", tab: tab)
      screenshot format("%02d-run-%s", 11 + index, tab), "#content"
      # README illustration: the consumption tab below the filters.
      screenshot "home", "#content", from: ".reporting-sticky", max_height: 820 if tab == "consumption"
    end
  end

  def test_08_build_and_workload_dashboards
    open_reporting(section: "build", tab: "build")
    screenshot "15-build", "#content"
    open_reporting(section: "build", tab: "burnup")
    screenshot "16-build-burnup", "#content"
    open_reporting(section: "workload", tab: "workload")
    screenshot "17-workload", "#content"
  end

  def test_09_chart_opens_native_list
    open_reporting(section: "run", tab: "flow")
    canvas = find("#flow-monthly")
    page.execute_script("arguments[0].scrollIntoView({block: 'center'})", canvas)
    point = page.evaluate_script(<<~JS)
      (() => {
        const chart = Chart.getChart(document.getElementById("flow-monthly"));
        const bar = chart.getDatasetMeta(0).data[chart.data.labels.length - 1];
        const box = chart.canvas.getBoundingClientRect();
        return {x: box.left + bar.x, y: box.top + bar.y};
      })()
    JS
    list = window_opened_by { page.driver.browser.action.move_to_location(point["x"].round, point["y"].round + 4).click.perform }
    within_window(list) do
      assert_current_path "/issues", ignore_query: true
      assert_selector "table.issues tbody tr"
      screenshot "18-drilldown-issues", "#content", max_height: 640
    end
    list.close
  end

  private

  # Demo issues and time without the configuration the document walks through:
  # the generator's role permissions, module, settings and root credits are removed first.
  def prepare_demo_project
    User.create!(login: ADMIN_LOGIN, firstname: "Redmine", lastname: "Admin", mail: "#{ADMIN_LOGIN}@example.invalid",
                 admin: true, language: "en", password: ADMIN_PASSWORD, password_confirmation: ADMIN_PASSWORD)
    RedmineReporting::DemoData.load
    project = Project.find_by!(identifier: PROJECT)
    Role.where(name: ROLES).each do |role|
      role.remove_permission!(:view_reporting, :manage_reporting)
    end
    # Subprojects keep the module: the walkthrough enables it on the root project only.
    project.disable_module!(:reporting)
    ReportingProjectSetting.where(project_id: project.self_and_descendants.select(:id)).delete_all
    project.reporting_credit_policies.destroy_all
    FileUtils.mkdir_p(SCREENSHOTS)
  end

  # Redmine's helper compares the current path without waiting on some versions.
  def log_user(login, password)
    visit "/my/page"
    assert_current_path "/login", ignore_query: true
    within("#login-form form") do
      fill_in "username", with: login
      fill_in "password", with: password
      find('input[name="login"]').click
    end
    assert_current_path "/my/page", ignore_query: true
  end

  def open_reporting(section:, tab:)
    from = Date.current.beginning_of_month << 11
    visit "/projects/#{PROJECT}/reporting?section=#{section}&tab=#{tab}&from=#{from}&to=#{Date.current}&grouping=month"
    assert_selector "#panel-#{tab}"
    wait_for_charts
  end

  # Date inputs follow the browser locale; setting the value avoids typing a localized format.
  def fill_date(id, date)
    page.execute_script("document.getElementById(arguments[0]).value = arguments[1]", id, date.iso8601)
  end

  def wait_for_charts
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until page.evaluate_script(<<~JS)
        typeof Chart !== "undefined" && [...document.querySelectorAll("canvas")].map(canvas => Chart.getChart(canvas))
          .filter(Boolean).every(chart => !Chart.animator.running(chart))
      JS
    end
  end

  # Captures one element of the page at a fixed desktop width. Redmine's top bar is hidden
  # unless it is the subject, and the viewport is stretched to the whole page so sticky
  # blocks and charts render where a reader sees them.
  def screenshot(name, target, width: 1280, max_height: nil, from: nil)
    browser = page.driver.browser
    element = target.is_a?(String) ? find(target) : target
    page.execute_script(<<~JS, element)
      const chrome = ["top-menu", "header", "footer"].map(id => document.getElementById(id)).filter(Boolean);
      chrome.forEach(block => { if (!block.contains(arguments[0])) block.style.display = "none"; });
    JS
    metrics = ->(height) { browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: height, deviceScaleFactor: 1, mobile: false) }
    metrics.call(900)
    page.execute_script("window.scrollTo(0, 0)")
    metrics.call([page.evaluate_script("document.documentElement.scrollHeight").to_i, 900].max)
    wait_for_charts if page.has_css?("canvas", wait: 0)
    # Redmine's content area keeps a minimum height: stop below its last visible block.
    box = page.evaluate_script(<<~JS, element)
      (() => {
        const box = arguments[0].getBoundingClientRect().toJSON();
        const bottoms = [...arguments[0].children].map(child => child.getBoundingClientRect())
          .filter(rect => rect.width > 0 && rect.height > 0).map(rect => rect.bottom);
        if (bottoms.length) box.height = Math.min(box.height, Math.max(...bottoms) + 8 - box.top);
        return box;
      })()
    JS
    if from
      top = page.evaluate_script("arguments[0].getBoundingClientRect().top", find(from))
      box["height"] -= top - box["top"]
      box["top"] = top
    end
    margin = 4
    height = box["height"] + 2 * margin
    clip = {
      x: [box["left"] - margin, 0].max, y: [box["top"] - margin, 0].max,
      width: box["width"] + 2 * margin, height: max_height ? [height, max_height].min : height, scale: 1
    }
    data = browser.execute_cdp("Page.captureScreenshot", format: "png", clip: clip, fromSurface: true)["data"]
    File.binwrite(File.join(SCREENSHOTS, "#{name}.png"), Base64.decode64(data))
  ensure
    browser&.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end
