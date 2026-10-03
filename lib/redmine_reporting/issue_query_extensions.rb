# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/issue_query_extensions.rb
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
  module IssueQueryExtensions
    def initialize_available_filters
      super
      add_available_filter "reporting_version_on", type: :date, name: l(:label_reporting_version_on)
      add_available_filter "reporting_completed_on", type: :date, name: l(:label_reporting_completed_on)
      add_available_filter "reporting_historical_version_id", type: :list_optional, name: l(:label_reporting_historical_version),
        values: -> { available_filters.fetch("fixed_version_id").values }
      add_available_filter "reporting_closed_on", type: :date_past, name: l(:label_reporting_closed_on)
      add_available_filter "reporting_backlog_on", type: :date, name: l(:label_reporting_backlog_on)
      add_available_filter "reporting_flow_on", type: :date_past, name: l(:label_reporting_flow_on)
    end

    def sql_for_reporting_version_on_field(_field, operator, values)
      return "1=0" unless operator == "="

      "issues.created_on < #{VersionHistory.cutoff(Date.iso8601(values.first.to_s), User.current)}"
    rescue Date::Error
      "1=0"
    end

    def sql_for_reporting_completed_on_field(_field, operator, values)
      return "1=0" unless operator == "="

      "NOT (#{IssueHistory.sql_open_on(Date.iso8601(values.first.to_s), User.current)})"
    rescue Date::Error
      "1=0"
    end

    def sql_for_reporting_historical_version_id_field(_field, operator, values)
      return "1=0" unless has_filter?("reporting_version_on") && operator_for("reporting_version_on") == "="

      expression = VersionHistory.sql_on(Date.iso8601(values_for("reporting_version_on").first.to_s), User.current)
      ids = values.map { |value| Issue.connection.quote(value.to_i.to_s) }
      case operator
      when "=" then ids.any? ? "#{expression} IN (#{ids.join(',')})" : "1=0"
      when "!" then ids.any? ? "(#{expression} IS NULL OR #{expression} NOT IN (#{ids.join(',')}))" : "1=1"
      when "*" then "#{expression} IS NOT NULL"
      when "!*" then "#{expression} IS NULL"
      else "1=0"
      end
    rescue Date::Error
      "1=0"
    end

    # Historical backlog includes both later closures and issues with no closure date.
    def sql_for_reporting_closed_on_field(field, operator, values)
      condition = sql_for_field(field, operator, values, Issue.table_name, "closed_on")
      "(#{Issue.table_name}.status_id IN (SELECT id FROM issue_statuses WHERE is_closed = #{Issue.connection.quoted_false}) OR #{Issue.table_name}.closed_on IS NULL OR (#{condition}))"
    end

    def sql_for_reporting_backlog_on_field(_field, operator, values)
      return "1=0" unless operator == "="

      date = Date.iso8601(values.first.to_s)
      RedmineReporting::IssueHistory.sql_open_on(date, User.current)
    rescue Date::Error
      "1=0"
    end

    # Period-label clicks select issues opened or closed within the same period.
    def sql_for_reporting_flow_on_field(field, operator, values)
      created = sql_for_field(field, operator, values, Issue.table_name, "created_on")
      closed = sql_for_field(field, operator, values, Issue.table_name, "closed_on")
      "((#{created}) OR (#{closed}))"
    end
  end
end
