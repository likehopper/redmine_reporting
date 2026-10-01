# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/summary.rb
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
    # Provider view of the period, over the issues of the period as filtered: what was
    # estimated, what was done, and what is left to do. It reads
    # estimated − done = left to do (open issues) + gap on closed issues.
    class Summary < Base
      def to_h
        result = {}
        result.merge!(issue_figures) if data.capabilities.issues?
        result[:spentDays] = round(days(time_entries.sum { |entry| entry.hours.to_f })) if data.capabilities.time?
        result.merge!(work_figures) if data.capabilities.issues? && data.capabilities.time?
        result
      end

      private

      def alive
        @alive ||= timelines.select { |timeline| timeline.alive_between?(first_day, last_day) }
      end

      def still_open
        @still_open ||= alive.reject(&:closed?)
      end

      def issue_figures
        closed = alive.length - still_open.length
        {issues: alive.length, openIssues: still_open.length, closedIssues: closed,
         closedRatio: alive.empty? ? 0 : (closed * 100.0 / alive.length).round}
      end

      def work_figures
        estimated, done = estimated_hours(alive), done_hours(alive)
        open_estimated, open_done = estimated_hours(still_open), done_hours(still_open)
        # Only open issues are left to do; negative when their estimate is overrun.
        remaining = open_estimated - open_done
        # Estimated minus done on closed issues: positive when they took less than planned.
        closed_gap = (estimated - open_estimated) - (done - open_done)
        {estimatedHours: round(estimated), doneHours: round(done), openEstimatedHours: round(open_estimated),
         openDoneHours: round(open_done), estimatedDays: round(days(estimated)), doneDays: round(days(done)),
         remainingDays: round(days(remaining)), closedGapDays: round(days(closed_gap)),
         progress: progress(done, remaining),
         # Counted as zero in the estimate, so their time widens the gap.
         unestimatedIssues: alive.count { |timeline| timeline.estimated_hours.nil? }}
      end

      def estimated_hours(timelines)
        timelines.sum { |timeline| timeline.estimated_hours.to_f }
      end

      def done_hours(timelines)
        timelines.sum { |timeline| spent_time.total(timeline.issue) }
      end

      # Done out of done plus left to do: 100% once nothing is left, overruns included.
      def progress(done, remaining)
        total = done + [remaining, 0].max
        total.positive? ? (done * 100 / total).round : 0
      end
    end
  end
end
