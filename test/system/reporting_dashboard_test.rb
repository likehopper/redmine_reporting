# frozen_string_literal: true

require_relative "../test_helper"

# Redmine 5.0's webdrivers gem predates current Chrome download URLs. CI uses
# the matching browser/driver pair installed by the OS instead of downloading one.
if ENV["CHROMEDRIVER_PATH"] && Gem.loaded_specs.key?("webdrivers")
  require "webdrivers/chromedriver"
  Selenium::WebDriver::Chrome::Service.driver_path = -> { ENV.fetch("CHROMEDRIVER_PATH") }
end
require File.expand_path("../../../../test/application_system_test_case", __dir__)

# Browser checks for what integration tests cannot see: the page script, chart clicks and layout.
class ReportingDashboardSystemTest < ApplicationSystemTestCase
  include ReportingTestData

  def test_every_chart_renders_inside_redmine_content
    open_dashboard
    assert_selector "#content > .reporting-sticky .reporting-banner"
    assert_selector "#content > main.reporting-sections #panel-flow"
    # The page script draws all tabs in one pass: an error would leave later canvases unbound.
    canvases = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".reporting-sections canvas")].map(canvas => [canvas.id, !!Chart.getChart(canvas)])
    JS
    assert_operator canvases.length, :>=, 10
    assert_empty canvases.reject(&:last).map(&:first)
    content, panel = bounds("content"), bounds("panel-flow")
    assert_operator panel["left"], :>=, content["left"]
    assert_operator panel["right"], :<=, content["right"]
  end

  def test_the_script_skips_charts_hidden_by_project_modules
    [@project, @child].each { |project| project.disable_module!(:time_tracking) }
    open_dashboard
    assert_no_selector "#tab-activity"
    unbound = page.evaluate_script(<<~JS)
      [...document.querySelectorAll(".reporting-sections canvas")].filter(canvas => !Chart.getChart(canvas)).map(canvas => canvas.id)
    JS
    assert_empty unbound
    # The last chart of the page script is drawn, so nothing stopped it on the way.
    assert page.evaluate_script("!!Chart.getChart(document.getElementById('aging'))")
  end

  def test_point_column_and_period_label_open_the_matching_issues
    open_dashboard
    last = chart_value("flow-monthly", "chart.data.labels.length - 1")
    point = chart_value("flow-monthly", "chart.getDatasetMeta(0).data[#{last}].getProps(['x', 'y'], true)")
    column = {"x" => point["x"], "y" => chart_value("flow-monthly", "chart.chartArea.top + 5")}
    label = {"x" => point["x"], "y" => chart_value("flow-monthly", "chart.chartArea.bottom + 8")}
    # Both issues were created today: the point, anywhere in its column and its month label all list them.
    [point, column, label].each do |position|
      assert_issue_list(count: 2) { click_chart("flow-monthly", position) }
    end
  end

  def test_remaining_time_card_lists_estimated_and_spent_totals
    @parent_issue.update_columns(estimated_hours: 10)
    @child_issue.update_columns(estimated_hours: 4)
    open_dashboard
    # 14 h estimated minus the child's 2 h spent, at 8 h per day.
    card = find(".reporting-kpi-group a.reporting-stat", text: "Time left")
    assert_includes card.text, "1.5d"
    assert_issue_list(count: 2, times: true) { card.click }
  end

  def test_labels_follow_the_user_language
    {"fr" => ["Flux des tickets", %w[Ouverts Fermés]], "en" => ["Issue flow", %w[Opened Closed]]}.each do |language, (tab, labels)|
      @administrator.update_columns(language: language)
      open_dashboard(login: language == "fr")
      assert_selector "#tab-flow", text: tab
      assert_equal labels, chart_value("flow-monthly", "chart.data.datasets.map(dataset => dataset.label)")
    end
  end

  def test_legends_use_the_right_on_wide_charts_and_bottom_on_small_screens
    page.current_window.resize_to(1600, 1000)
    open_dashboard
    %w[flow-tracker flow-priority].each do |id|
      assert_equal "right", chart_value(id, "chart.legend.position")
      assert_operator chart_value(id, "chart.legend.left"), :>=, chart_value(id, "chart.chartArea.right")
    end
    # The paired opened/closed datasets still toggle together from the legend.
    entry = chart_value("flow-tracker", "chart.legend.legendHitBoxes[0]")
    click_chart("flow-tracker", {"x" => entry["left"] + 5, "y" => entry["top"] + 5})
    assert_equal [false, false], chart_value("flow-tracker", "[chart.isDatasetVisible(0), chart.isDatasetVisible(1)]")
    click_chart("flow-tracker", {"x" => entry["left"] + 5, "y" => entry["top"] + 5})
    wait_for_charts
    page.save_screenshot("/artifacts/legends-desktop.png") if File.directory?("/artifacts")
    page.current_window.resize_to(390, 844)
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until chart_value("flow-tracker", "chart.options.plugins.legend.position") == "bottom"
    end
    page.save_screenshot("/artifacts/legends-mobile.png") if File.directory?("/artifacts")
    assert_equal "bottom", chart_value("flow-tracker", "chart.options.plugins.legend.position")
    content, panel = bounds("content"), bounds("panel-flow")
    assert_operator panel["right"], :<=, content["right"] + 1
  ensure
    page.current_window.resize_to(1024, 900)
  end

  def test_time_only_dashboard_renders_without_issue_data
    [@project, @child].each { |project| project.disable_module!(:issue_tracking) }
    log_user(@administrator.login, "Reporting-test-123!")
    visit "/projects/#{@project.identifier}/reporting"
    assert_selector "#time-user"
    wait_for_charts
    assert page.evaluate_script("!!Chart.getChart(document.getElementById('consumption-contract'))")
    data = JSON.parse(find("#report-data", visible: false).text(:all))
    refute data.key?("issueFlow")
    refute data["summary"].key?("estimatedHours")
  end

  private

  # Redmine 5.0's helper compares current_path without waiting for navigation.
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

  def open_dashboard(login: true)
    log_user(@administrator.login, "Reporting-test-123!") if login
    visit "/projects/#{@project.identifier}/reporting"
    assert_selector "#flow-monthly"
    wait_for_charts
  end

  # Positions are read once animations are over, so clicks land where Chart.js expects them.
  def wait_for_charts
    Timeout.timeout(Capybara.default_max_wait_time) do
      sleep 0.1 until page.evaluate_script(<<~JS)
        typeof Chart !== "undefined" && [...document.querySelectorAll("canvas")].map(canvas => Chart.getChart(canvas))
          .filter(Boolean).every(chart => !Chart.animator.running(chart))
      JS
    end
  end

  def chart_value(id, expression)
    page.evaluate_script("(() => { const chart = Chart.getChart(document.getElementById('#{id}')); return #{expression}; })()")
  end

  def bounds(id)
    page.evaluate_script("document.getElementById('#{id}').getBoundingClientRect().toJSON()")
  end

  # Viewport coordinates avoid Selenium 3/4's different element-offset conventions.
  def click_chart(id, position)
    canvas = find("##{id}")
    page.execute_script("arguments[0].scrollIntoView({block: 'center'})", canvas)
    size = bounds(id)
    page.driver.browser.action.
      move_to_location((size["left"] + position["x"]).round, (size["top"] + position["y"]).round).
      click.perform
  end

  def assert_issue_list(count:, times: false, &)
    list = window_opened_by(&)
    within_window(list) do
      assert_current_path "/issues", ignore_query: true
      assert_selector "table.issues tbody tr", count: count
      if times
        assert_selector "table.issues td.estimated_hours", count: count
        assert_selector "table.issues td.spent_hours", count: count
        assert_selector ".query-totals .total-for-estimated-hours"
        assert_selector ".query-totals .total-for-spent-hours"
      end
    end
    list.close
  end
end
