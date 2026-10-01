# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/time_entry_query_extensions.rb
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
