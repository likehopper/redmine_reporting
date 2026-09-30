# frozen_string_literal: true

module RedmineReporting
  # One step of a report axis. Its calendar start keys chart links; its first and last days
  # are clamped to the report dates, so a partial month only covers the selected days.
  Period = Struct.new(:start_on, :first_day, :last_day, :label, keyword_init: true) do
    def include?(date)
      date.present? && date >= first_day && date <= last_day
    end

    def start
      start_on.iso8601
    end
  end

  # Consecutive day, week, month or quarter periods covering a date range.
  class PeriodGrid
    include Enumerable

    GROUPINGS = %w[day week month quarter].freeze

    attr_reader :grouping, :first_day, :last_day

    def self.months(first_day, last_day)
      new(first_day.beginning_of_month, last_day, "month")
    end

    def initialize(first_day, last_day, grouping = "month")
      @first_day = first_day.to_date
      @last_day = last_day.to_date
      @grouping = GROUPINGS.include?(grouping.to_s) ? grouping.to_s : "month"
    end

    def each(&)
      periods.each(&)
    end

    def periods
      @periods ||= begin
        list = []
        start = start_of(@first_day)
        while start <= @last_day
          list << Period.new(start_on: start, first_day: [start, @first_day].max, last_day: [finish_of(start), @last_day].min,
                             label: label_of(start))
          start = next_start(start)
        end
        list
      end
    end

    def labels
      map(&:label)
    end

    def starts
      map(&:start)
    end

    private

    def start_of(date)
      case @grouping
      when "day" then date
      when "week" then date.beginning_of_week
      when "quarter" then date.beginning_of_quarter
      else date.beginning_of_month
      end
    end

    def finish_of(start)
      case @grouping
      when "day" then start
      when "week" then start + 6
      when "quarter" then start.end_of_quarter
      else start.end_of_month
      end
    end

    def next_start(start)
      finish_of(start) + 1
    end

    def label_of(start)
      case @grouping
      when "day" then ::I18n.l(start, format: ::I18n.t("reporting.periods.day_format"))
      when "week"
        format = ::I18n.t("reporting.periods.week_format")
        "#{::I18n.l(start, format: format)} – #{::I18n.l(start + 6, format: format)}"
      when "quarter" then ::I18n.t("reporting.periods.quarter", quarter: (start.month - 1) / 3 + 1, year: start.year)
      else ::I18n.l(start, format: ::I18n.t("reporting.periods.month_format"))
      end
    end
  end
end
