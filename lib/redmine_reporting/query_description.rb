# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/query_description.rb
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
  class QueryDescription < SimpleDelegator
    include Redmine::I18n

    # "Tracker is Bug, Support request" for each native filter except the project scope.
    def readable_filters
      filters.except("project_id").filter_map do |field, filter|
        definition = available_filters[field]
        next unless definition

        values = Array(filter[:values]).reject(&:blank?)
        if definition[:values] && values.any?
          options = definition.values.to_h { |option| [option[1].to_s, option[0]] }
          values = values.map { |value| options.fetch(value.to_s, value) }
        end
        [definition[:name], l(Query.operators[filter[:operator]]), values.join(", ").presence].compact.join(" ")
      end
    end

    # "eCookbook and its 3 subprojects", or the selected project names.
    def readable_projects
      projects = selected_projects.to_a
      return l(:"reporting.scope.no_project") if projects.empty?
      if !has_filter?("project_id") && projects.length > 1
        return l(:"reporting.scope.project_with_subprojects", project: projects.first.name, count: projects.length - 1)
      end

      names = projects.first(3).map(&:name)
      names << l(:"reporting.scope.other_projects", count: projects.length - 3) if projects.length > 3
      names.to_sentence
    end

  end
end
