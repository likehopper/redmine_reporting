# frozen_string_literal: true

module RedmineReporting
  # Assembles the dashboard payload: one report per tab, over the same loaded data.
  class ReportBuilder
    REPORTS = {
      summary: Reports::Summary, issueFlow: Reports::Flow, activity: Reports::Activity,
      consumption: Reports::Consumption, backlog: Reports::Backlog, performance: Reports::Performance
    }.freeze

    def initialize(query:, first_day:, last_day:, grouping: "month", hours_per_day: ReportingProjectSetting::DEFAULT_HOURS_PER_DAY)
      @query = query
      @data = ReportData.new(query: query, first_day: first_day, last_day: last_day, grouping: grouping, hours_per_day: hours_per_day)
    end

    def allowed?(name)
      return true if name == :summary
      return @data.capabilities.time? if [:activity, :consumption].include?(name)

      @data.capabilities.issues?
    end

    def build
      {
        dateFrom: @data.first_day.iso8601,
        dateTo: @data.last_day.iso8601,
        queryParams: @query.as_params.to_query,
        grouping: @data.grid.grouping,
        **REPORTS.select { |name, _| allowed?(name) }.transform_values { |report| report.new(@data).to_h }
      }
    end
  end
end
