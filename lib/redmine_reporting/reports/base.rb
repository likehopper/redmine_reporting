# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/base.rb
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
        counts = items.each_with_object(Hash.new(0)) { |item, totals| totals[date.call(item)] += 1 }
        grid.map { |period| (period.first_day..period.last_day).sum { |day| counts[day] } }
      end

      def round(value)
        (value.to_f * 100).round / 100.0
      end
    end
  end
end
