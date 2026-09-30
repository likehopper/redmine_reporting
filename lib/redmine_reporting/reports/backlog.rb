# frozen_string_literal: true

module RedmineReporting
  module Reports
    # Issues not closed yet at the end of each period, and their time left at that date.
    class Backlog < Base
      def to_h
        snapshots = grid.map { |period| [period, timelines.select { |timeline| timeline.in_backlog_on?(period.last_day) }] }
        trackers = sorted(timelines.map(&:tracker))

        {
          periodLabels: grid.labels,
          periodStarts: grid.starts,
          trackerSeries: series(trackers, snapshots, :tracker) { |items| items.length },
          prioritySeries: series(sorted_priorities(timelines), snapshots, :priority) { |items| items.length },
          remainingSeries: series(trackers, snapshots, :tracker) { |items, period| round(remaining_hours(items, period)) },
          remainingTotal: snapshots.map { |period, items| round(remaining_hours(items, period)) }
        }
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
