# frozen_string_literal: true
# File: redmine_reporting/test/unit/period_grid_test.rb
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

require_relative "../test_helper"

class PeriodGridTest < ActiveSupport::TestCase
  def test_partial_months_are_clamped_but_keep_their_calendar_start
    grid = RedmineReporting::PeriodGrid.new(Date.new(2026, 1, 15), Date.new(2026, 3, 10), "month")
    assert_equal %w[2026-01-01 2026-02-01 2026-03-01], grid.starts
    assert_equal [Date.new(2026, 1, 15), Date.new(2026, 1, 31)], [grid.first.first_day, grid.first.last_day]
    assert_equal Date.new(2026, 3, 10), grid.periods.last.last_day
    refute grid.first.include?(Date.new(2026, 1, 14))
    refute grid.periods.last.include?(Date.new(2026, 3, 11))
  end

  def test_weeks_start_on_monday_and_quarters_on_their_first_month
    weeks = RedmineReporting::PeriodGrid.new(Date.new(2026, 1, 7), Date.new(2026, 1, 20), "week")
    assert_equal %w[2026-01-05 2026-01-12 2026-01-19], weeks.starts
    quarters = RedmineReporting::PeriodGrid.new(Date.new(2026, 2, 1), Date.new(2026, 7, 1), "quarter")
    assert_equal %w[2026-01-01 2026-04-01 2026-07-01], quarters.starts
    days = RedmineReporting::PeriodGrid.new(Date.new(2026, 1, 1), Date.new(2026, 1, 3), "day")
    assert_equal 3, days.count
    # Unknown groupings fall back to months.
    assert_equal "month", RedmineReporting::PeriodGrid.new(Date.new(2026, 1, 1), Date.new(2026, 1, 3), "year").grouping
  end

  def test_labels_follow_the_locale
    grid = RedmineReporting::PeriodGrid.new(Date.new(2026, 2, 1), Date.new(2026, 2, 20), "quarter")
    assert_equal ["T1 2026"], ::I18n.with_locale(:fr) { grid.labels }
    assert_equal ["Q1 2026"], ::I18n.with_locale(:en) { RedmineReporting::PeriodGrid.new(grid.first_day, grid.last_day, "quarter").labels }
    months = ::I18n.with_locale(:en) { RedmineReporting::PeriodGrid.months(Date.new(2026, 1, 1), Date.new(2026, 1, 31)).labels }
    assert_equal ["Jan 26"], months
  end
end
