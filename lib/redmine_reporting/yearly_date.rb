# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/yearly_date.rb
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
