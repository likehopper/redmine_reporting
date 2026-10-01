# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/backlog.rb
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
    # Issues not closed yet at the end of each period, and their time left at that date.
    class Backlog < Base
      def to_h
        snapshots = grid.map { |period| [period, timelines.select { |timeline| timeline.in_backlog_on?(period.last_day) }] }
        trackers = sorted(timelines.map(&:tracker))

        result = {
          periodLabels: grid.labels,
          periodStarts: grid.starts,
          periodRanges: grid.ranges,
          trackerSeries: series(trackers, snapshots, :tracker) { |items| items.length },
          prioritySeries: series(sorted_priorities(timelines), snapshots, :priority) { |items| items.length }
        }
        if data.capabilities.time?
          result[:remainingSeries] = series(trackers, snapshots, :tracker) { |items, period| round(remaining_hours(items, period)) }
          result[:remainingTotal] = snapshots.map { |period, items| round(remaining_hours(items, period)) }
        end
        result
      end

      private

      def series(groups, snapshots, attribute, &value)
        groups.map do |group|
          {label: group.name, data: snapshots.map { |period, items| value.call(items.select { |item| item.public_send(attribute) == group }, period) }}
        end
      end

      # Estimated minus spent up to the period end: negative on overruns.
      def remaining_hours(items, period)
        items.sum { |timeline| timeline.estimated_hours.to_f - spent_time.until(timeline.issue, period.last_day) }
      end
    end
  end
end
