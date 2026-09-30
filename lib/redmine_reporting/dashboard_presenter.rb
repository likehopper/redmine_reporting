# frozen_string_literal: true

module RedmineReporting
  # Dashboard descriptions and links share the exact period and query of the report.
  # The view supplies Redmine's localization, number formatting and route helpers.
  class DashboardPresenter
    attr_reader :description

    def initialize(view:, query:, grid:, report:, hours_per_day:)
      @view, @query, @grid, @report = view, query, grid, report
      @hours_per_day = hours_per_day
      @description = QueryDescription.new(query)
    end

    def date_from
      @view.format_date(@grid.first_day)
    end

    def date_to
      @view.format_date(@grid.last_day)
    end

    def hours_per_day
      @view.reporting_hours(@hours_per_day)
    end

    def scope(tab)
      values = {from: date_from, to: date_to, hours: hours_per_day,
                grouping: @view.l("label_reporting_grouping_#{@grid.grouping}").downcase}
      if tab == "consumption"
        contract_start = @report.dig(:consumption, :contract, :periodStarts)&.first
        values[:contract] = contract_start ? @view.l(:"reporting.scope.consumption_contract", date: @view.format_date(Date.iso8601(contract_start))) : ""
      end
      @view.l(:"reporting.scope.#{tab}", **values)
    end

    def details_path(**selection)
      @view.project_reporting_details_path(project_id: @query.project, from: @grid.first_day,
        to: @grid.last_day, **@query.as_params, **selection)
    end

    def active_issue_parameters
      {records: "issues", created_to: @grid.last_day, closed_before: @grid.first_day - 1}
    end
  end
end
