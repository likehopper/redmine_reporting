# frozen_string_literal: true

require_relative "../test_helper"

class CreditLedgerTest < ActiveSupport::TestCase
  fixtures :reporting_credit_policies, :reporting_credit_refills

  def setup
    @policies = ReportingCreditPolicy.active.where(project_id: 1).includes(:reporting_credit_refills).to_a
  end

  def test_monthly_balance_with_grants_refills_and_consumption
    ledger = ledger(Date.new(2026, 1, 1), Date.new(2026, 12, 31), {1 => 10, 7 => 30, 8 => 20})
    january, july, august = ledger.rows.values_at(0, 6, 7)
    # January: 20 + 20 + 10 granted, 10 consumed.
    assert_equal [50, 0, 50, 40], [january.granted, january.refilled, january.credit_before, january.balance]
    assert_in_delta 40 / 12.0, january.horizon
    # July: two 5-day refills on top of the 40 left.
    assert_equal [0, 10, 50, 20], [july.granted, july.refilled, july.credit_before, july.balance]
    assert_equal [0, 60], [august.credit, august.cumulative_spent]
    # Grants and refills together.
    assert_equal [60, 60, 60, 0, 100], [ledger.granted, ledger.available, ledger.consumed, ledger.remaining, ledger.progress]
  end

  def test_an_overrun_is_paid_back_by_later_grants_while_credit_stays_at_zero
    ledger = ledger(Date.new(2026, 12, 1), Date.new(2027, 1, 31), {12 => 70})
    december, january = ledger.rows
    assert_equal [-70, 0], [december.balance, december.credit]
    # January 2027: Feature and Support are granted again (Bug ended with 2026).
    assert_equal [40, -30, 0], [january.granted, january.balance, january.credit]
    assert_equal 0, ledger.remaining
    # 70 days consumed out of the 40 available: the overrun shows above 100%.
    assert_equal [40, 70, 175], [ledger.available, ledger.consumed, ledger.progress]
  end

  def test_an_opening_balance_starts_the_period
    ledger = ledger(Date.new(2026, 7, 1), Date.new(2026, 12, 31), {8 => 2}, opening_balance: 7)
    assert_equal [7, 17, 17], [ledger.opening_balance, ledger.rows.first.credit_before, ledger.available]
    assert_equal [2, 15], [ledger.consumed, ledger.remaining]
  end

  def test_accounts_add_up_without_sharing_credit
    ahead = ledger(Date.new(2026, 7, 1), Date.new(2026, 7, 31), {7 => 4}, opening_balance: 5, policies: [])
    overdrawn = ledger(Date.new(2026, 7, 1), Date.new(2026, 7, 31), {7 => 3}, opening_balance: -2, policies: [])
    total = RedmineReporting::CreditLedger.sum([ahead, overdrawn])
    assert_equal [3, 7], [total.opening_balance, total.consumed]
    # The overdrawn account keeps its debt: 5 available and 1 left, not 3 and 0.
    assert_equal [5, 1], [total.available, total.remaining]
    assert_equal [-4, 1], [total.rows.first.balance, total.rows.first.credit]
  end

  def test_no_policy_means_no_credit_and_no_progress
    ledger = RedmineReporting::CreditLedger.build(policies: [], spent_days: {}, months: months(Date.new(2026, 1, 1), Date.new(2026, 3, 31)))
    assert_equal [0, 0, 0], [ledger.available, ledger.remaining, ledger.progress]
    assert_equal 3, ledger.rows.length
  end

  private

  def months(first_day, last_day)
    RedmineReporting::PeriodGrid.months(first_day, last_day)
  end

  # spent: {month number => days}, in the year of the month.
  def ledger(first_day, last_day, spent, opening_balance: 0.0, policies: @policies)
    grid = months(first_day, last_day)
    spent_days = grid.to_h { |month| [month.start_on, spent.fetch(month.start_on.month, 0).to_f] }
    RedmineReporting::CreditLedger.build(policies: policies, spent_days: spent_days, months: grid, opening_balance: opening_balance)
  end
end
