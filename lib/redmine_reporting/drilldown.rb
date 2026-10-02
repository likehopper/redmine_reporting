# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/drilldown.rb
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
  # Translate chart selections into editable native queries, never lists of record IDs.
  class Drilldown
    include Rails.application.routes.url_helpers

    def self.build(reporting_query, parameters)
      (parameters[:records] == "time_entries" ? TimeEntryDrilldown : IssueDrilldown).new(reporting_query, parameters)
    end

    def initialize(reporting_query, parameters)
      @reporting_query = reporting_query
      @parameters = parameters
      @query = query_class.new(name: "Reporting")
      @query.filters = {}
      project_ids = reporting_query.selected_projects.ids.map(&:to_s)
      @query.add_filter("project_id", "=", project_ids.presence || ["0"])
      filters = reporting_query.valid? ? reporting_query.filters.except("project_id") : {}
      if parameters[:version_at].present? && parameters[:records] != "time_entries"
        filters = filters.except("fixed_version_id")
      end
      filters.each do |field, filter|
        @query.add_filter(native_field(field), filter[:operator], filter[:values].dup)
      end
      apply_selection
    end

    def path
      public_send(route_name, @query.as_params.slice(:f, :op, :v, :set_filter).merge(sort: "id:asc", **list_options))
    end

    private

    def list_options
      {}
    end

    def native_field(field)
      field
    end

    def restrict(field, identifiers)
      identifiers = identifiers.map(&:to_s)
      if @query.has_filter?(field)
        case @query.operator_for(field)
        when "=" then identifiers &= @query.values_for(field)
        when "!" then identifiers -= @query.values_for(field)
        when "!*" then identifiers = []
        end
      end
      @query.add_filter(field, "=", identifiers.presence || ["0"])
    end

    def restrict_named(field, model, parameter)
      name = @parameters[parameter]
      restrict(native_field(field), model.where(name: name).ids) if name.present?
    end

    def date_parameter(name)
      Date.iso8601(@parameters[name].to_s) if @parameters[name].present?
    rescue Date::Error
      nil
    end

    def date_filter(field, first_date, last_date)
      if first_date && last_date
        @query.add_filter(field, "><", [first_date.iso8601, last_date.iso8601])
      elsif first_date
        @query.add_filter(field, ">=", [first_date.iso8601])
      elsif last_date
        @query.add_filter(field, "<=", [last_date.iso8601])
      end
    end
  end

  class IssueDrilldown < Drilldown
    TIME_COLUMNS = %w[estimated_hours spent_hours].freeze

    private

    def query_class
      IssueQuery
    end

    # Remaining-time figures open with estimated and spent columns, totaled by Redmine.
    def list_options
      return {} unless @parameters[:times] == "true"

      {c: ["project", *Setting.issue_list_default_columns.map(&:to_s), *TIME_COLUMNS].uniq, t: TIME_COLUMNS}
    end

    def route_name
      :issues_path
    end

    def apply_selection
      restrict("tracker_id", @reporting_query.run_tracker_ids) unless @reporting_query.run_tracker_ids.nil?
      restrict_named("tracker_id", Tracker, :tracker)
      restrict_named("priority_id", IssuePriority, :priority)
      restrict_named("status_id", IssueStatus, :status)
      if @parameters[:version_at].present?
        if (date = date_parameter(:version_at))
          @query.add_filter("reporting_version_on", "=", [date.iso8601])
          @query.add_filter("reporting_completed_on", "=", [date.iso8601]) if @parameters[:completed] == "true"
          field = "reporting_historical_version_id"
          if @reporting_query.has_filter?("fixed_version_id")
            @query.add_filter(field, @reporting_query.operator_for("fixed_version_id"), @reporting_query.values_for("fixed_version_id"))
          end
          if @parameters[:historical_version_id] == "none"
            excludes_null = @query.has_filter?(field) && %w[= *].include?(@query.operator_for(field))
            excludes_null ? restrict(field, []) : @query.add_filter(field, "!*", [""])
          else
            restrict(field, [@parameters[:historical_version_id].to_i])
          end
        else
          restrict("project_id", [])
        end
      end
      if @parameters[:version_id].present?
        if @parameters[:version_id] == "none"
          if @reporting_query.issue_scope.where(fixed_version_id: nil).exists?
            @query.add_filter("fixed_version_id", "!*", [""])
          else
            restrict("fixed_version_id", [])
          end
        else
          restrict("fixed_version_id", [@parameters[:version_id]])
        end
      end
      date_filter("due_date", nil, date_parameter(:due_before))
      date_filter("created_on", date_parameter(:created_from), date_parameter(:created_to))
      date_filter("closed_on", date_parameter(:closed_from), date_parameter(:closed_to))
      date_filter("reporting_flow_on", date_parameter(:flow_from), date_parameter(:flow_to))
      if (snapshot_date = date_parameter(:backlog_at))
        date_filter("created_on", nil, snapshot_date)
        @query.add_filter("reporting_backlog_on", "=", [snapshot_date.iso8601])
      end
      if !snapshot_date && (open_date = date_parameter(:closed_before))
        date_filter("reporting_closed_on", open_date + 1, nil)
      end
      # Redmine keeps closed_on on reopened issues: charts counting closed issues check the status too.
      restrict("status_id", IssueStatus.where(is_closed: false).ids) if @parameters[:open] == "true"
      restrict("status_id", IssueStatus.where(is_closed: true).ids) if @parameters[:closed] == "true"
      if (bounds = Reports::Performance::AGE_BUCKETS[@parameters[:age]])
        reference_date = date_parameter(:as_of) || User.current.today
        minimum_age, maximum_age = bounds
        date_filter("created_on", maximum_age && reference_date - maximum_age, reference_date - minimum_age)
      end
    end
  end

  class TimeEntryDrilldown < Drilldown
    private

    # Same rule as ReportingQuery#time_entry_scope: time without an issue stays, unless issues are filtered.
    def apply_run_perimeter(issue_filtered)
      run_ids = @reporting_query.run_tracker_ids
      return if run_ids.nil?

      if issue_filtered || @reporting_query.section == "build"
        restrict("issue.tracker_id", run_ids)
      elsif (other_ids = Tracker.where.not(id: run_ids).ids).any?
        # Redmine's "is not" also keeps entries without an issue.
        @query.add_filter("issue.tracker_id", "!", other_ids.map(&:to_s))
      end
    end

    def query_class
      TimeEntryQuery
    end

    def route_name
      :time_entries_path
    end

    def native_field(field)
      "issue.#{field}"
    end

    def apply_selection
      # Null issue attributes must not include entries without an issue.
      issue_filtered = @reporting_query.filters.keys.any? { |field| field != "project_id" }
      @query.add_filter("issue_id", "*", [""]) if issue_filtered
      apply_run_perimeter(issue_filtered)
      date_filter("spent_on", date_parameter(:from), date_parameter(:to))
      restrict_named("tracker_id", Tracker, :tracker)
      restrict_named("priority_id", IssuePriority, :priority)
      if @parameters[:activity_id].present?
        restrict("activity_id", TimeEntryActivity.where(id: @parameters[:activity_id]).ids)
      elsif @parameters[:activity].present?
        restrict("activity_id", TimeEntryActivity.where(name: @parameters[:activity]).ids)
      end
      if @parameters[:user_id].present?
        restrict("user_id", User.where(id: @reporting_query.time_entry_scope.select(:user_id)).where(id: @parameters[:user_id]).ids)
      end
      if @parameters[:user].present?
        # Restrict the lookup to contributors; inactive users and namesakes still count.
        contributors = User.where(id: @reporting_query.time_entry_scope.select(:user_id))
        restrict("user_id", contributors.select { |user| user.name == @parameters[:user] }.map(&:id))
      end
    end
  end
end
