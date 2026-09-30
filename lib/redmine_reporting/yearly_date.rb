# frozen_string_literal: true

module RedmineReporting
  # A day of the year repeated every year (anniversaries, refills). February 29 falls on
  # February 28 in non-leap years, and any day past the end of a month on its last day.
  module YearlyDate
    def self.date(year, month, day)
      Date.new(year, month, [day, Date.new(year, month, -1).day].min)
    end

    # Occurrences of the yearly date within the range, whatever its length.
    def self.between(month, day, first_day, last_day)
      (first_day.year..last_day.year).map { |year| date(year, month, day) }.select { |date| date.between?(first_day, last_day) }
    end

    def self.within?(date, from, to)
      (from.nil? || date >= from) && (to.nil? || date <= to)
    end
  end
end
