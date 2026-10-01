# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/flow.rb
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
    # Issues created and closed over the period, per tracker, priority and status.
    class Flow < Base
      def to_h
        opened = timelines.select { |timeline| timeline.created_between?(first_day, last_day) }
        closed = timelines.select { |timeline| timeline.closed_between?(first_day, last_day) }
        opened_counts = counts_per_period(opened, &:created_on)
        closed_counts = counts_per_period(closed, &:closed_on)
        open_statuses = status_counts(timelines.reject(&:closed?))
        closed_statuses = status_counts(closed.select(&:closed?))

        {
          periodLabels: grid.labels,
          periodStarts: grid.starts,
          periodRanges: grid.ranges,
          opened: opened_counts,
          closed: closed_counts,
          # Cumulated over the period only; earlier history is never included.
          cumulativeCreated: cumulate(opened_counts),
          cumulativeClosed: cumulate(closed_counts),
          trackerFlow: mirrored(sorted(timelines.map(&:tracker)), opened, closed, :tracker),
          priorityFlow: mirrored(sorted_priorities(timelines), opened, closed, :priority),
          openStatusLabels: open_statuses.keys,
          openStatusValues: open_statuses.values,
          closedStatusLabels: closed_statuses.keys,
          closedStatusValues: closed_statuses.values
        }
      end

      private

      # Creations above zero and closures below, so a same-period creation and closure both show.
      def mirrored(groups, opened, closed, attribute)
        groups.map do |group|
          {
            label: group.name,
            opened: counts_per_period(opened.select { |timeline| timeline.public_send(attribute) == group }, &:created_on),
            closed: counts_per_period(closed.select { |timeline| timeline.public_send(attribute) == group }, &:closed_on).map(&:-@)
          }
        end
      end

      # Most frequent status first, then Redmine's status order.
      def status_counts(items)
        items.group_by(&:status).sort_by { |status, group| [-group.length, status] }.to_h { |status, group| [status.name, group.length] }
      end

      def cumulate(counts)
        total = 0
        counts.map { |count| total += count }
      end
    end
  end
end
