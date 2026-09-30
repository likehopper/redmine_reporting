# frozen_string_literal: true

module RedmineReporting
  module Reports
    # One dashboard tab: turns the report data into the series its charts draw.
    class Base
      def initialize(data)
        @data = data
      end

      private

      attr_reader :data

      delegate :grid, :timelines, :time_entries, :spent_time, :policies, :first_day, :last_day, :days, to: :data

      # Redmine records in Redmine's own order (tracker, status and enumeration positions).
      def sorted(records)
        records.compact.uniq.sort
      end

      # Highest priority first, as issue lists read them.
      def sorted_priorities(items)
        sorted(items.map(&:priority)).reverse
      end

      def counts_per_period(items, &date)
        grid.map { |period| items.count { |item| period.include?(date.call(item)) } }
      end

      def round(value)
        (value.to_f * 100).round / 100.0
      end
    end
  end
end
