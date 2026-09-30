# frozen_string_literal: true

require_relative "../test_helper"

class ReportingNavigationTest < ActionDispatch::IntegrationTest
  include ReportingTestData

  def test_controller_renders_native_filters_and_preserves_them_in_details
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    # Parsed as a browser does: a stray closing tag would move the dashboard out of Redmine's #content.
    page = Nokogiri::HTML5(session.response.body)
    assert page.at_css("#content > .reporting-sticky .reporting-banner"), "banner outside #content"
    assert page.at_css("#content > main.reporting-sections #panel-flow"), "charts outside #content"
    report = JSON.parse(page.at_css("#report-data").text)
    assert_equal 2, report.fetch("issueFlow").fetch("opened").sum
    refute_includes report.fetch("queryParams"), "project_id"
    parameters = {f: ["project_id"], op: {"project_id" => "!"}, v: {"project_id" => [@project.id.to_s]}}
    session.get "/projects/#{@project.identifier}/reporting", params: parameters
    assert_equal 200, session.response.status, session.response.body.first(500)
    assert_includes session.response.body, 'id="add_filter_select"'
    assert_includes session.response.body, 'id="query_form"'
    refute_includes session.response.body, "translation missing"
    session.get "/projects/#{@project.identifier}/reporting/details", params: parameters
    assert_equal 302, session.response.status
    assert_equal "/issues", URI(session.response.location).path
    session.follow_redirect!
    assert_equal 200, session.response.status
    document = Nokogiri::HTML(session.response.body)
    assert_equal [@child_issue.id.to_s], document.css("table.issues tbody tr td.id a").map(&:text)
    session.get "/queries/filter", params: {type: "ReportingQuery", project_id: @project.id, name: "project_id"}
    assert_equal 200, session.response.status
    assert_equal [@project.id, @child.id].sort, JSON.parse(session.response.body).map { |_, identifier| identifier.to_i }.sort
  end

  def test_mirrored_flow_opens_eight_creations_and_two_closures
    closed_status = IssueStatus.where(is_closed: true).first!
    closed_issues = [@parent_issue, @child_issue]
    closed_issues.each do |issue|
      issue.update_columns(created_on: Time.utc(2026, 1, 5), closed_on: Time.utc(2026, 1, 20), status_id: closed_status.id)
    end
    created_issues = closed_issues + Array.new(6) do
      issue = create_issue(@project)
      issue.update_columns(created_on: Time.utc(2026, 1, 10))
      issue
    end
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting", params: {from: "2026-01-01", to: "2026-01-31"}
    assert_equal 200, session.response.status
    flow = JSON.parse(Nokogiri::HTML5(session.response.body).at_css("#report-data").text).fetch("issueFlow")
    %w[trackerFlow priorityFlow].each do |dimension|
      assert_equal [8], flow.fetch(dimension).first.fetch("opened")
      assert_equal [-2], flow.fetch(dimension).first.fetch("closed")
    end

    {tracker: @tracker.name, priority: @parent_issue.priority.name}.each do |dimension, name|
      [[:created, created_issues], [:closed, closed_issues]].each do |event, expected_issues|
        session.get "/projects/#{@project.identifier}/reporting/details", params: {
          records: "issues", dimension => name,
          "#{event}_from" => "2026-01-01", "#{event}_to" => "2026-01-31"
        }
        assert_equal 302, session.response.status
        parameters = Rack::Utils.parse_nested_query(URI(session.response.location).query)
        refute_includes parameters.fetch("f"), "status_id"
        session.follow_redirect!
        assert_equal 200, session.response.status
        document = Nokogiri::HTML5(session.response.body)
        assert_equal expected_issues.map(&:id).sort, document.css("table.issues tbody tr td.id a").map { |link| link.text.to_i }.sort
      end
    end
    session.get "/projects/#{@project.identifier}/reporting/details", params: {flow_from: "2026-01-01", flow_to: "2026-01-31"}
    session.follow_redirect!
    assert_equal 200, session.response.status
    document = Nokogiri::HTML5(session.response.body)
    assert_equal created_issues.map(&:id).sort, document.css("table.issues tbody tr td.id a").map { |link| link.text.to_i }.sort
  end

  def test_filtered_cumulative_counts_match_the_native_lists
    closed_status = IssueStatus.where(is_closed: true).first!
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 1), closed_on: Time.utc(2026, 1, 20), status_id: closed_status.id)
    @child_issue.update_columns(created_on: Time.utc(2026, 1, 20), closed_on: Time.utc(2026, 2, 10), status_id: closed_status.id)
    boundary_issue = create_issue(@project)
    boundary_issue.update_columns(created_on: Time.utc(2026, 1, 15), closed_on: Time.utc(2026, 2, 15, 23, 59), status_id: closed_status.id)
    earlier_issue = create_issue(@project)
    earlier_issue.update_columns(created_on: Time.utc(2025, 12, 1), closed_on: Time.utc(2026, 1, 14))
    later_issue = create_issue(@project)
    later_issue.update_columns(created_on: Time.utc(2026, 2, 16), closed_on: Time.utc(2026, 2, 20))
    session = authenticated_session(@administrator)
    session.get "/projects/#{@project.identifier}/reporting", params: {from: "2026-01-15", to: "2026-02-15"}
    assert_equal 200, session.response.status
    flow = JSON.parse(Nokogiri::HTML5(session.response.body).at_css("#report-data").text).fetch("issueFlow")
    assert_equal [2, 2], flow.fetch("cumulativeCreated")
    assert_equal [1, 3], flow.fetch("cumulativeClosed")

    ["2026-01-31", "2026-02-15"].each_with_index do |period_end, index|
      expected_creations = [@child_issue.id, boundary_issue.id]
      expected_closures = index.zero? ? [@parent_issue.id] : [@parent_issue.id, @child_issue.id, boundary_issue.id]
      {created: expected_creations, closed: expected_closures, flow: expected_creations | expected_closures}.each do |event, expected_ids|
        session.get "/projects/#{@project.identifier}/reporting/details", params: {
          records: "issues", "#{event}_from" => "2026-01-15", "#{event}_to" => period_end
        }
        assert_equal 302, session.response.status
        session.follow_redirect!
        assert_equal 200, session.response.status
        document = Nokogiri::HTML5(session.response.body)
        actual_ids = document.css("table.issues tbody tr td.id a").map { |link| link.text.to_i }
        assert_equal expected_ids.sort, actual_ids.sort
        series = {created: "cumulativeCreated", closed: "cumulativeClosed"}[event]
        assert_equal flow.fetch(series)[index], actual_ids.length if series
      end
    end
  end

  def test_time_entry_redirect_renders_the_native_filtered_list
    session = authenticated_session(@administrator)
    parameters = {
      records: "time_entries", from: Date.current.iso8601, to: Date.current.iso8601,
      f: %w[priority_id fixed_version_id],
      op: {"priority_id" => "=", "fixed_version_id" => "*"},
      v: {"priority_id" => [@child_issue.priority_id.to_s], "fixed_version_id" => [""]}
    }
    session.get "/projects/#{@project.identifier}/reporting/details", params: parameters
    assert_equal 302, session.response.status
    assert_equal "/time_entries", URI(session.response.location).path
    session.follow_redirect!
    assert_equal 200, session.response.status
    document = Nokogiri::HTML5(session.response.body)
    assert_equal ["time-entry-#{@entry.id}"], document.css("table.time-entries tr.time-entry").map { |row| row["id"] }
    assert document.at_css("#query_form"), "native time-entry filters are missing"
  end

  def test_dashboard_follows_the_user_language
    {"fr" => ["Flux des tickets", "Reste à passer", "Taux de résolution"],
     "en" => ["Issue flow", "Time left", "Resolution rate"]}.each do |language, texts|
      @administrator.update_columns(language: language)
      session = authenticated_session(@administrator)
      session.get "/projects/#{@project.identifier}/reporting", params: {grouping: "quarter", tab: "backlog"}
      assert_equal 200, session.response.status
      body = session.response.body
      texts.each { |text| assert_includes body, text, language }
      refute_includes body, "translation missing"
      page = Nokogiri::HTML5(body)
      strings = JSON.parse(page.at_css("#report-i18n").text)
      assert_equal ::I18n.t("reporting.js", locale: language).keys.map(&:to_s).sort, strings.keys.sort
      quarter = JSON.parse(page.at_css("#report-data").text).dig("backlog", "periodLabels").first
      assert_match(language == "fr" ? /\AT[1-4] \d{4}\z/ : /\AQ[1-4] \d{4}\z/, quarter)
    end
  end

  def test_request_permissions_and_filter_options
    session = authenticated_session(create_viewer)
    session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 200, session.response.status
    session.get "/queries/filter", params: {type: "ReportingQuery", project_id: @project.id, name: "project_id"}
    assert_equal 200, session.response.status
    assert_equal [[@project.name, @project.id.to_s]], JSON.parse(session.response.body)
    session.get "/projects/#{@child.identifier}/reporting/details"
    assert_equal 403, session.response.status
    session.get "/queries/filter", params: {type: "ReportingQuery", project_id: @child.id, name: "project_id"}
    assert_equal 403, session.response.status
    anonymous_session = ActionDispatch::Integration::Session.new(Rails.application)
    anonymous_session.get "/projects/#{@project.identifier}/reporting"
    assert_equal 302, anonymous_session.response.status
  end

end
