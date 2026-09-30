# frozen_string_literal: true

module RedmineReporting
  # Month by month balance of credit policies against consumed days. The balance carries
  # over: an overrun is paid back by later grants, while displayed credit never goes below zero.
  class CreditLedger
    Row = Struct.new(:period, :granted, :refilled, :spent, :credit_before, :balance, :horizon, :cumulative_spent,
                     keyword_init: true) do
      def credit
        [balance, 0].max
      end
    end

    attr_reader :rows

    # spent_days: {first day of month => consumed days}
    def initialize(policies:, spent_days:, months:)
      @months = months
      @rows = build_rows(policies, spent_days)
    end

    def granted
      rows.sum(&:granted)
    end

    def refilled
      rows.sum(&:refilled)
    end

    def consumed
      rows.sum(&:spent)
    end

    def remaining
      rows.last ? rows.last.credit : 0.0
    end

    def available
      granted + refilled
    end

    def progress
      available.zero? ? 0 : (consumed * 100 / available).round
    end

    private

    def build_rows(policies, spent_days)
      balance = 0.0
      cumulative = 0.0
      @months.each_with_index.map do |month, index|
        granted = policies.sum { |policy| policy.granted_days_between(month.first_day, month.last_day) }
        refilled = policies.sum { |policy| policy.refilled_days_between(month.first_day, month.last_day) }
        spent = spent_days.fetch(month.start_on, 0.0)
        balance += granted + refilled
        credit_before = balance
        balance -= spent
        cumulative += spent
        # Spread what is left over the months that remain, current month included.
        horizon = [balance, 0].max / (@months.count - index)
        Row.new(period: month, granted: granted, refilled: refilled, spent: spent, credit_before: credit_before,
                balance: balance, horizon: horizon, cumulative_spent: cumulative)
      end
    end
  end
end
