# frozen_string_literal: true

module RedmineReporting
  # Month by month balance of credit policies against charged days, from an opening
  # balance. The balance carries over: an overrun is paid back by later grants, while
  # displayed credit never goes below zero.
  class CreditLedger
    Row = Struct.new(:period, :granted, :refilled, :spent, :credit_before, :balance, :credit, :horizon, :cumulative_spent,
                     keyword_init: true)

    attr_reader :rows, :opening_balance

    # spent_days: {first day of month => charged days}
    def self.build(policies:, spent_days:, months:, opening_balance: 0.0)
      balance = opening_balance
      cumulative = 0.0
      rows = months.each_with_index.map do |month, index|
        granted = policies.sum { |policy| policy.granted_days_between(month.first_day, month.last_day) }
        refilled = policies.sum { |policy| policy.refilled_days_between(month.first_day, month.last_day) }
        spent = spent_days.fetch(month.start_on, 0.0)
        balance += granted + refilled
        credit_before = balance
        balance -= spent
        cumulative += spent
        # Spread what is left over the months that remain, current month included.
        horizon = [balance, 0].max / (months.count - index)
        Row.new(period: month, granted: granted, refilled: refilled, spent: spent, credit_before: credit_before,
                balance: balance, credit: [balance, 0].max, horizon: horizon, cumulative_spent: cumulative)
      end
      new(rows: rows, opening_balance: opening_balance)
    end

    # Several accounts over the same months, added up row by row. Credit and availability
    # add up per account, so an overrun on one account never eats another one's credit.
    def self.sum(ledgers)
      return new(rows: [], opening_balance: 0.0) if ledgers.empty?

      fields = Row.members - [:period]
      rows = ledgers.map(&:rows).transpose.map do |month_rows|
        Row.new(period: month_rows.first.period, **fields.to_h { |field| [field, month_rows.sum(&field)] })
      end
      new(rows: rows, opening_balance: ledgers.sum(&:opening_balance), parts: ledgers)
    end

    def initialize(rows:, opening_balance:, parts: nil)
      @rows = rows
      @opening_balance = opening_balance
      @parts = parts
    end

    def granted
      rows.sum(&:granted) + rows.sum(&:refilled)
    end

    def consumed
      rows.sum(&:spent)
    end

    def available
      @parts ? @parts.sum(&:available) : [opening_balance + granted, 0].max
    end

    def remaining
      @parts ? @parts.sum(&:remaining) : [closing_balance, 0].max
    end

    def closing_balance
      rows.last ? rows.last.balance : opening_balance
    end

    def progress
      return consumed.positive? ? 100 : 0 if available.zero?

      (consumed * 100 / available).round
    end
  end
end
