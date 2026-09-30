# frozen_string_literal: true

module RedmineReporting
  module TimeEntryQueryExtensions
    def initialize_available_filters
      super
      add_available_filter "issue.priority_id", type: :list,
        name: l(:label_attribute_of_issue, name: l(:field_priority)),
        values: -> { IssuePriority.active.sorted.map { |priority| [priority.name, priority.id.to_s] } }
      # Preserve Redmine's value provider while allowing versions that are not set.
      version_filter = available_filters.fetch("issue.fixed_version_id")
      add_available_filter "issue.fixed_version_id", type: :list_optional,
        name: version_filter[:name], values: -> { version_filter.values }
    end

    def sql_for_issue_priority_id_field(field, operator, values)
      sql_for_field(field, operator, values, Issue.table_name, "priority_id")
    end

    def sql_for_issue_fixed_version_id_field(field, operator, values)
      # Use the joined issue instead of materializing every matching issue ID.
      sql_for_field(field, operator, values, Issue.table_name, "fixed_version_id")
    end
  end
end
