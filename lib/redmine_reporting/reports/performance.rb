# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/performance.rb
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
    # Issues closed over the period (velocity, resolution time) and age of those still open.
    class Performance < Base
      # Age buckets in days since creation, shared with the issue lists they open.
      AGE_BUCKETS = {"lt7" => [0, 6], "7-30" => [7, 29], "30-90" => [30, 89], "90-180" => [90, 179], "gt180" => [180, nil]}.freeze

      def to_h
        closed = timelines.select { |timeline| timeline.closed? && timeline.closed_between?(first_day, last_day) }
        by_priority = sorted_priorities(closed).to_h { |priority| [priority, closed.select { |timeline| timeline.priority == priority }] }
        open = timelines.reject(&:closed?)

        {
          periodLabels: grid.labels,
          periodStarts: grid.starts,
          periodRanges: grid.ranges,
          velocity: counts_per_period(closed, &:closed_on),
          resolutionLabels: by_priority.keys.map(&:name),
          resolutionDays: by_priority.values.map { |items| round(items.sum(&:resolution_days).to_f / items.length) },
          resolutionCounts: by_priority.values.map(&:length),
          agingKeys: AGE_BUCKETS.keys,
          agingLabels: AGE_BUCKETS.keys.map { |key| ::I18n.t(key, scope: "reporting.aging") },
          agingValues: AGE_BUCKETS.values.map do |min, max|
            open.count { |timeline| timeline.age_on(last_day).then { |age| age >= min && (max.nil? || age <= max) } }
          end
        }
      end
    end
  end
end
