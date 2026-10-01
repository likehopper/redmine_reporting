# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/period_grid.rb
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

    MAX_PERIODS = 600
    InvalidRange = Class.new(ArgumentError)

    GROUPINGS = %w[day week month quarter].freeze

    attr_reader :grouping, :first_day, :last_day

    def self.from_params(from:, to:, grouping:, today:)
      last = to.present? ? Date.iso8601(to.to_s) : today
      first = from.present? ? Date.iso8601(from.to_s) : (last << 11).beginning_of_month
      new(*[first, last].minmax, grouping)
    rescue Date::Error
      raise InvalidRange
    end

    def self.months(first_day, last_day)
      new(first_day.beginning_of_month, last_day, "month")
    end

    def initialize(first_day, last_day, grouping = "month")
      @first_day = first_day.to_date
      @last_day = last_day.to_date
      @grouping = GROUPINGS.include?(grouping.to_s) ? grouping.to_s : "month"
      raise InvalidRange unless @first_day.year.between?(1900, 2200) && @last_day.year.between?(1900, 2200) && @first_day <= @last_day
      span = case @grouping
             when "day" then (@last_day - @first_day).to_i + 1
             when "week" then ((@last_day.beginning_of_week - @first_day.beginning_of_week).to_i / 7) + 1
             when "quarter" then (@last_day.year * 4 + (@last_day.month - 1) / 3) - (@first_day.year * 4 + (@first_day.month - 1) / 3) + 1
             else (@last_day.year * 12 + @last_day.month) - (@first_day.year * 12 + @first_day.month) + 1
             end
      raise InvalidRange if span > MAX_PERIODS
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

    def ranges
      map { |period| {from: period.first_day.iso8601, to: period.last_day.iso8601} }
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
