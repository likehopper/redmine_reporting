# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/burnup.rb
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
    class Burnup
      def initialize(data)
        @data = data
      end

      def to_h
        return {versions: [], labels: [], dates: []} unless @data.capabilities.issues?

        # Version filters apply to membership at each snapshot, not today's membership.
        query = ReportingQuery.new(name: "Burnup", project: @data.query.project, user: @data.user)
        query.run_tracker_ids = @data.query.run_tracker_ids
        query.filters = @data.query.filters.except("fixed_version_id")
        issues = @data.query.valid? ? query.issue_scope.to_a : []
        events = JournalDetail.joins(:journal).where(property: "attr", prop_key: %w[fixed_version_id status_id],
          journals: {journalized_type: "Issue", journalized_id: issues.map(&:id)}).
          order("journals.created_on", "journals.id", "journal_details.id").
          pluck("journals.journalized_id", :prop_key, "journals.created_on", :old_value, :value).group_by(&:first)
        statuses = IssueStatus.all.to_a
        closed_ids = statuses.select(&:is_closed).map(&:id)
        histories = issues.map do |issue|
          rows = Array(events[issue.id])
          [@data.user.time_to_date(issue.created_on),
           VersionHistory.new(issue, @data.user, rows.select { |row| row[1] == "fixed_version_id" }.map { |row| row.drop(2) }),
           IssueHistory.new(issue, @data.user, rows.select { |row| row[1] == "status_id" }.map { |row| row.drop(2) }, closed_ids, statuses.map(&:id))]
        end
        periods = @data.grid.select { |period| period.first_day <= @data.user.today }
        dates = periods.map { |period| [period.last_day, @data.user.today].min }
        snapshots = dates.map do |date|
          totals = Hash.new { |hash, key| hash[key] = [0, 0] }
          histories.each do |created, version, status|
            next if created > date

            id = version.on(date)
            totals[id][0] += 1
            totals[id][1] += 1 unless status.open_on?(date)
          end
          totals
        end
        ids = snapshots.flat_map(&:keys).uniq
        versions = Version.visible(@data.user).where(id: ids.compact).includes(:project).index_by(&:id)
        rows = ids.filter_map do |id|
          next if id && !versions.key?(id)
          next unless selected?(id)

          version = versions[id]
          {id: id, name: version && "#{version.project.name} · #{version.name}",
           scope: snapshots.map { |totals| totals.fetch(id, [0, 0])[0] },
           completed: snapshots.map { |totals| totals.fetch(id, [0, 0])[1] }}
        end
        {versions: rows.sort_by { |row| [row[:id] ? 0 : 1, row[:name].to_s, row[:id].to_i] }, labels: periods.map(&:label), dates: dates.map(&:iso8601)}
      end

      private

      def selected?(id)
        query = @data.query
        return true unless query.has_filter?("fixed_version_id")

        ids = query.values_for("fixed_version_id").map(&:to_i)
        case query.operator_for("fixed_version_id")
        when "=" then ids.include?(id)
        when "!" then !ids.include?(id)
        when "*" then !id.nil?
        when "!*" then id.nil?
        else false
        end
      end
    end
  end
end
