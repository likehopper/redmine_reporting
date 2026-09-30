# frozen_string_literal: true

module RedmineReporting
  module Reports
    # Banner figures: issues open during the period, time spent and time left on those still open.
    class Summary < Base
      def to_h
        alive = timelines.select { |timeline| timeline.alive_between?(first_day, last_day) }
        still_open = alive.reject(&:closed?)
        closed = alive.length - still_open.length
        # Same balance as the totals of their native list: negative on overruns.
        estimated_hours = still_open.sum { |timeline| timeline.estimated_hours.to_f }
        spent_hours = still_open.sum { |timeline| spent_time.total(timeline.issue) }

        {
          issues: alive.length,
          openIssues: still_open.length,
          closedIssues: closed,
          closedRatio: alive.empty? ? 0 : (closed * 100.0 / alive.length).round,
          spentDays: round(days(time_entries.sum { |entry| entry.hours.to_f })),
          estimatedHours: round(estimated_hours),
          issueSpentHours: round(spent_hours),
          remainingDays: round(days(estimated_hours - spent_hours)),
          spentRatio: estimated_hours.zero? ? 0 : (spent_hours * 100 / estimated_hours).round
        }
      end
    end
  end
end
