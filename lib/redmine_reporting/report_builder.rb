# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/report_builder.rb
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
      if @query.section == "workload"
        return {dateFrom: @data.first_day.iso8601, dateTo: @data.last_day.iso8601,
                queryParams: @query.as_params.to_query, workload: Reports::Workload.new(@data).to_h}
      end

      if @query.section == "build"
        return {dateFrom: @data.first_day.iso8601, dateTo: @data.last_day.iso8601,
                queryParams: @query.as_params.to_query, build: Reports::Build.new(@data).to_h}
      end

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
