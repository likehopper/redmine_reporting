# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/build.rb
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
    # Current delivery scope: no historical claim about version membership or estimates.
    class Build
      def initialize(data)
        @data = data
      end

      def to_h
        return {versions: []} unless @data.capabilities.issues?

        issues = @data.query.issue_scope.includes(:status).to_a
        versions = Version.visible(@data.user).where(id: issues.map(&:fixed_version_id).compact).includes(:project).index_by(&:id)
        spent = @data.query.time_entry_scope.group(:issue_id).sum(:hours) if @data.capabilities.time?
        rows = issues.group_by(&:fixed_version_id).filter_map do |id, items|
          version = versions[id]
          next if id && !version

          open = items.reject { |issue| issue.status.is_closed? }
          row = {id: id, name: version ? "#{version.project.name} · #{version.name}" : nil,
                 dueDate: version&.effective_date&.iso8601,
                 open: open.length, closed: items.length - open.length,
                 overdue: open.count { |issue| issue.due_date && issue.due_date < @data.user.today },
                 progress: (100.0 * (items.length - open.length) / items.length).round(1)}
          if spent
            row.merge!(estimated: items.sum { |issue| issue.estimated_hours.to_f }.round(2),
                       spent: items.sum { |issue| spent.fetch(issue.id, 0).to_f }.round(2),
                       remaining: open.sum { |issue| [issue.estimated_hours.to_f - spent.fetch(issue.id, 0).to_f, 0].max }.round(2),
                       overrun: items.sum { |issue| [spent.fetch(issue.id, 0).to_f - issue.estimated_hours.to_f, 0].max }.round(2))
          end
          row
        end
        {versions: rows.sort_by { |row| [row[:id] ? 0 : 1, row[:dueDate] || "9999", row[:name].to_s] },
         today: @data.user.today.iso8601}
      end
    end
  end
end
