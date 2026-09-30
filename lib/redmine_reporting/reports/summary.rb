# frozen_string_literal: true

module RedmineReporting
  module Reports
    class Summary < Base
      def to_h
        result = {}
        result.merge!(issue_figures) if data.capabilities.issues?
        result[:spentDays] = round(days(time_entries.sum { |entry| entry.hours.to_f })) if data.capabilities.time?
        result.merge!(remaining_figures) if data.capabilities.issues? && data.capabilities.time?
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

      def remaining_figures
        estimated = still_open.sum { |timeline| timeline.estimated_hours.to_f }
        spent = still_open.sum { |timeline| spent_time.total(timeline.issue) }
        {estimatedHours: round(estimated), issueSpentHours: round(spent), remainingDays: round(days(estimated - spent)),
         spentRatio: estimated.zero? ? 0 : (spent * 100 / estimated).round}
      end
    end
  end
end
