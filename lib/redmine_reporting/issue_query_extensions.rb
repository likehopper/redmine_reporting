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
    include ContractFilters

    def initialize_available_filters
      super
      add_contract_filters
      add_available_filter "reporting_version_on", type: :date, name: l(:label_reporting_version_on)
      add_available_filter "reporting_completed_on", type: :date, name: l(:label_reporting_completed_on)
      add_available_filter "reporting_historical_version_id", type: :list_optional, name: l(:label_reporting_historical_version),
        values: -> { available_filters.fetch("fixed_version_id").values }
      add_available_filter "reporting_closed_on", type: :date_past, name: l(:label_reporting_closed_on)
      add_available_filter "reporting_backlog_on", type: :date, name: l(:label_reporting_backlog_on)
      add_available_filter "reporting_flow_on", type: :date_past, name: l(:label_reporting_flow_on)
      add_sla_filters
    end

    # Per SLA type: when its delay ended, and its time used against the term.
    def add_sla_filters
      return unless SlaFigures.installed?

      ::SlaType.sorted.each do |type|
        add_available_filter "reporting_sla_end_#{type.id}", type: :date_past,
          name: l(:label_reporting_sla_end, type: type.name)
        add_available_filter "reporting_sla_time_#{type.id}", type: :list,
          name: l(:label_reporting_sla_time, type: type.name),
          values: -> { SlaFigures::BUCKETS.keys.map { |bucket| [l(:"reporting.sla.buckets.#{bucket}"), bucket] } }
      end
    end

    def respond_to_missing?(name, include_private = false)
      name.to_s.match?(/\Asql_for_reporting_sla_(end|time)_\d+_field\z/) || super
    end

    def method_missing(name, *arguments, &block)
      match = name.to_s.match(/\Asql_for_reporting_sla_(end|time)_(\d+)_field\z/)
      return super unless match

      match[1] == "end" ? sql_for_sla_end(match[2].to_i, *arguments) : sql_for_sla_time(match[2].to_i, *arguments)
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

    private

    # Same rule as IssueTimeline#left_on: out of the type's statuses now, last left then.
    def sql_for_sla_end(type_id, field, operator, values)
      status_ids = ::SlaStatus.where(sla_type_id: type_id).pluck(:status_id)
      return "1=0" if status_ids.empty?

      condition = sql_for_field(field, operator, values, "rsla", "ended_on")
      "(#{Issue.table_name}.status_id NOT IN (#{status_ids.map(&:to_i).join(',')}) AND #{Issue.table_name}.id IN " \
        "(SELECT rsla.issue_id FROM (#{IssueHistory.sql_left(status_ids)}) rsla WHERE #{condition}))"
    end

    def sql_for_sla_time(type_id, _field, operator, values)
      buckets = values & SlaFigures::BUCKETS.keys
      return(operator == "!" ? "1=1" : "1=0") if buckets.empty?

      "#{Issue.table_name}.id #{operator == '!' ? 'NOT IN' : 'IN'} (#{SlaFigures.sql_issue_ids(type_id, buckets)})"
    end
  end
end
