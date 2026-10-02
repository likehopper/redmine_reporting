# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/workload.rb
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
  module Reports
    # Current assignments and period activity have different dates and people:
    # time logged by a contributor is not necessarily on their assigned issues.
    class Workload
      def initialize(data)
        @data = data
      end

      def to_h
        result = {}
        if @data.capabilities.issues?
          issues = @data.query.issue_scope.open.includes(:assigned_to).to_a
          result[:assignees] = group(issues) do |items|
            {count: items.length, unestimated: items.count { |issue| issue.estimated_hours.to_f <= 0 }}
          end
          if @data.capabilities.time?
            eligible = @data.query.effort_project_ids
            effort_issues = issues.select { |issue| eligible.include?(issue.project_id) }
            spent = @data.query.time_entry_scope.where(issue_id: effort_issues.map(&:id)).group(:issue_id).sum(:hours)
            result[:remaining] = group(effort_issues) do |items|
              {hours: items.sum { |issue| [issue.estimated_hours.to_f - spent.fetch(issue.id, 0).to_f, 0].max }.round(2)}
            end
          end
        end
        if @data.capabilities.time?
          result[:contributors] = @data.time_entries.group_by(&:user).map do |user, entries|
            {id: user.id, name: user.name, hours: entries.sum { |entry| entry.hours.to_f }.round(2)}
          end.sort_by { |row| [row[:name], row[:id]] }
        end
        result
      end

      private

      def group(issues)
        issues.group_by(&:assigned_to).map do |assignee, items|
          {id: assignee&.id, name: assignee&.name, **yield(items)}
        end.sort_by { |row| [row[:id] ? 0 : 1, row[:name].to_s, row[:id].to_i] }
      end
    end
  end
end
