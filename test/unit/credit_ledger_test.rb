# frozen_string_literal: true

require_relative "../test_helper"

class CreditLedgerTest < ActiveSupport::TestCase
  fixtures :reporting_credit_policies, :reporting_credit_refills

  def setup
    @policies = ReportingCreditPolicy.active.where(project_id: 1).includes(:reporting_credit_refills).to_a
  end

  def test_monthly_balance_with_grants_refills_and_consumption
    ledger = ledger(Date.new(2026, 1, 1), Date.new(2026, 12, 31), 1 => 10, 7 => 30, 8 => 20)
    january, july, august = ledger.rows.values_at(0, 6, 7)
    # January: 20 + 20 + 10 granted, 10 consumed.
    assert_equal [50, 0, 50, 40], [january.granted, january.refilled, january.credit_before, january.balance]
    assert_in_delta 40 / 12.0, january.horizon
    # July: two 5-day refills on top of the 40 left.
    assert_equal [0, 10, 50, 20], [july.granted, july.refilled, july.credit_before, july.balance]
    assert_equal [0, 60], [august.credit, august.cumulative_spent]
    assert_equal [50, 10, 60, 60, 0, 100], [ledger.granted, ledger.refilled, ledger.available, ledger.consumed, ledger.remaining,
                                            ledger.progress]
  end

  def test_an_overrun_is_paid_back_by_later_grants_while_credit_stays_at_zero
    ledger = ledger(Date.new(2026, 12, 1), Date.new(2027, 1, 31), 12 => 70)
    december, january = ledger.rows
    assert_equal [-70, 0], [december.balance, december.credit]
    # January 2027: Feature and Support are granted again (Bug ended with 2026).
    assert_equal [40, -30, 0], [january.granted, january.balance, january.credit]
    assert_equal 0, ledger.remaining
  end

  def test_no_policy_means_no_credit_and_no_progress
    ledger = RedmineReporting::CreditLedger.new(policies: [], spent_days: {}, months: months(Date.new(2026, 1, 1), Date.new(2026, 3, 31)))
    assert_equal [0, 0, 0], [ledger.available, ledger.remaining, ledger.progress]
    assert_equal 3, ledger.rows.length
  end

  private

  def months(first_day, last_day)
    RedmineReporting::PeriodGrid.months(first_day, last_day)
  end

  # spent: {month number => days}, in the year of the month.
  def ledger(first_day, last_day, spent)
    grid = months(first_day, last_day)
    spent_days = grid.to_h { |month| [month.start_on, spent.fetch(month.start_on.month, 0).to_f] }
    RedmineReporting::CreditLedger.new(policies: @policies, spent_days: spent_days, months: grid)
  end
end
