# frozen_string_literal: true
require_relative "../test_helper"

class IssueHistoryTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_multiple_closures_and_reopenings_match_native_backlog_in_the_viewers_zone
    @administrator.pref.update!(time_zone: "Paris")
    opened = @parent_issue.status
    closed = IssueStatus.where(is_closed: true).first!
    @parent_issue.update_columns(created_on: Time.utc(2026, 1, 1), closed_on: Time.utc(2026, 3, 20), status_id: closed.id)
    transitions = [[Time.utc(2026, 1, 20), opened.id, closed.id],
                   [Time.utc(2026, 2, 1, 23, 30), closed.id, opened.id],
                   [Time.utc(2026, 3, 20), opened.id, closed.id]]
    transitions.each do |time, from, to|
      journal = Journal.create!(journalized: @parent_issue, user: @administrator, created_on: time)
      journal.details.create!(property: "attr", prop_key: "status_id", old_value: from.to_s, value: to.to_s)
    end
    query = build_query
    query.add_filter("project_id", "=", [@project.id.to_s])
    {"2026-01-19" => 1, "2026-01-20" => 0, "2026-02-01" => 0, "2026-02-02" => 1, "2026-03-20" => 0}.each do |date, count|
      day = Date.iso8601(date)
      report = RedmineReporting::ReportBuilder.new(query: query, first_day: day, last_day: day, grouping: "day").build
      assert_equal count, report[:backlog][:trackerSeries].sum { |series| series[:data].first }, date
      uri = URI(RedmineReporting::Drilldown.build(query, {backlog_at: date}).path)
      native = IssueQuery.new(name: "History")
      native.build_from_params(Rack::Utils.parse_nested_query(uri.query).with_indifferent_access)
      assert_equal count, native.issue_count, date
    end
  end
end
