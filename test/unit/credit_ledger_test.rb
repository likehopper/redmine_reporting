# frozen_string_literal: true
# File: redmine_reporting/test/unit/credit_ledger_test.rb
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

class CreditLedgerTest < ActiveSupport::TestCase
  # An envelope granted on a given date, with dated movements: {Date => days}.
  Envelope = Struct.new(:grant_on, :days, :movements) do
    def granted_days_between(first_day, last_day)
      grant_on.between?(first_day, last_day) ? days : 0.0
    end

    def refilled_days_between(first_day, last_day)
      movements.sum { |date, value| date.between?(first_day, last_day) ? value : 0.0 }
    end
  end

  def setup
    @envelopes = [Envelope.new(Date.new(2026, 1, 1), 30.0, {Date.new(2026, 7, 1) => 10.0}),
                  Envelope.new(Date.new(2026, 1, 1), 20.0, {})]
  end

  def test_monthly_balance_with_grants_movements_and_consumption
    ledger = ledger(Date.new(2026, 1, 1), Date.new(2026, 12, 31), {1 => 10, 7 => 30, 8 => 20})
    january, july, august = ledger.rows.values_at(0, 6, 7)
    assert_equal [50, 0, 50, 40], [january.granted, january.refilled, january.credit_before, january.balance]
    assert_in_delta 40 / 12.0, january.horizon
    assert_equal [0, 10, 50, 20], [july.granted, july.refilled, july.credit_before, july.balance]
    assert_equal [0, 60], [august.credit, august.cumulative_spent]
    assert_equal [60, 60, 60, 0, 100], [ledger.granted, ledger.available, ledger.consumed, ledger.remaining, ledger.progress]
  end

  def test_an_overrun_stays_as_debt_while_credit_shows_zero
    ledger = ledger(Date.new(2026, 1, 1), Date.new(2026, 2, 28), {1 => 70})
    january, february = ledger.rows
    assert_equal [-20, 0], [january.balance, january.credit]
    assert_equal [-20, 0], [february.balance, february.credit]
    # 70 days consumed out of the 50 available: the overrun shows above 100%.
    assert_equal [50, 70, 0, 140], [ledger.available, ledger.consumed, ledger.remaining, ledger.progress]
  end

  def test_an_adjustment_reduces_the_balance
    envelope = Envelope.new(Date.new(2026, 1, 1), 10.0, {Date.new(2026, 1, 1) => -3.0})
    ledger = ledger(Date.new(2026, 1, 1), Date.new(2026, 1, 31), {}, envelopes: [envelope])
    assert_equal [10, -3, 7], [ledger.rows.first.granted, ledger.rows.first.refilled, ledger.remaining]
  end

  def test_an_opening_balance_starts_the_period
    ledger = ledger(Date.new(2026, 7, 1), Date.new(2026, 12, 31), {8 => 2}, opening_balance: 7, envelopes: [])
    assert_equal [7, 7, 7], [ledger.opening_balance, ledger.rows.first.credit_before, ledger.available]
    assert_equal [2, 5], [ledger.consumed, ledger.remaining]
  end

  def test_parts_add_up_without_sharing_credit
    ahead = ledger(Date.new(2026, 7, 1), Date.new(2026, 7, 31), {7 => 4}, opening_balance: 5, envelopes: [])
    overdrawn = ledger(Date.new(2026, 7, 1), Date.new(2026, 7, 31), {7 => 3}, opening_balance: -2, envelopes: [])
    total = RedmineReporting::CreditLedger.sum([ahead, overdrawn])
    assert_equal [3, 7], [total.opening_balance, total.consumed]
    # The overdrawn part keeps its debt: 5 available and 1 left, not 3 and 0.
    assert_equal [5, 1], [total.available, total.remaining]
    assert_equal [-4, 1], [total.rows.first.balance, total.rows.first.credit]
  end

  def test_no_envelope_means_no_credit_and_no_progress
    ledger = RedmineReporting::CreditLedger.build(envelopes: [], spent_days: {}, months: months(Date.new(2026, 1, 1), Date.new(2026, 3, 31)))
    assert_equal [0, 0, 0], [ledger.available, ledger.remaining, ledger.progress]
    assert_equal 3, ledger.rows.length
  end

  private

  def months(first_day, last_day)
    RedmineReporting::PeriodGrid.months(first_day, last_day)
  end

  # spent: {month number => days}, in the year of the month.
  def ledger(first_day, last_day, spent, opening_balance: 0.0, envelopes: @envelopes)
    grid = months(first_day, last_day)
    spent_days = grid.to_h { |month| [month.start_on, spent.fetch(month.start_on.month, 0).to_f] }
    RedmineReporting::CreditLedger.build(envelopes: envelopes, spent_days: spent_days, months: grid, opening_balance: opening_balance)
  end
end
