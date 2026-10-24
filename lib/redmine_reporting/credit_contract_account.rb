# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/credit_contract_account.rb
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
  # One contract's credit, envelope by envelope. A contract starts from zero on its first
  # day and stops on its last one: nothing carries over unless a movement of the next
  # contract says so. Any period within it opens with the balance on its first day.
  class CreditContractAccount
    attr_reader :contract

    # hours: {project_id => hours per day}, for every project the contract may cover.
    def initialize(contract, scope:, hours:, default_hours: ReportingProjectSetting::DEFAULT_HOURS_PER_DAY)
      @contract = contract
      @scope = scope
      @hours = hours
      @default_hours = default_hours.to_f
    end

    def envelopes
      contract.live_envelopes
    end

    # The part of the range within the contract, month by month; nil outside it.
    def months(first_day, last_day)
      first = [first_day, contract.starts_on].max
      last = [last_day, contract.ends_on].min
      first > last ? nil : PeriodGrid.new(first, last, "month")
    end

    def ledger(first_day, last_day)
      ledgers = envelopes.filter_map { |envelope| envelope_ledger(envelope, first_day, last_day) }
      ledgers.empty? ? nil : CreditLedger.sum(ledgers)
    end

    # The contract over every month of a grid, so that contracts add up month by month: no
    # credit before it starts, none left after it ends (unless carried over by the next one).
    def ledger_on(grid)
      CreditLedger.sum(envelopes.map { |envelope| pad(envelope_ledger(envelope, grid.first_day, grid.last_day), grid) })
    end

    def envelope_ledger(envelope, first_day, last_day)
      grid = months(first_day, last_day)
      return unless grid

      opening = 0.0
      if grid.first_day > contract.starts_on
        history = PeriodGrid.new(contract.starts_on, grid.first_day - 1, "month")
        opening = build(envelope, history, 0.0).closing_balance
      end
      build(envelope, grid, opening)
    end

    # Balance on the contract's last day, before any carry-over.
    def closing_balance(envelope)
      envelope_ledger(envelope, contract.starts_on, contract.ends_on).closing_balance
    end

    # Days carried over into later contracts (negative for a debt taken over).
    def carried_out(envelope)
      envelope.carried_movements.sum { |movement| movement.days.to_f }
    end

    # Charged days per day over the whole contract: {date => days}.
    def spent_days(envelope)
      @spent_days ||= {}
      @spent_days[envelope.object_id] ||=
        TimeEntry.where(@scope.envelope_condition(envelope)).group(:project_id, :spent_on).sum(:hours).
          each_with_object(Hash.new(0.0)) do |((project_id, spent_on), hours), totals|
            totals[spent_on.to_date] += hours.to_f / @hours.fetch(project_id, @default_hours)
          end
    end

    private

    def pad(ledger, grid)
      own = ledger ? ledger.rows.index_by { |row| row.period.start_on } : {}
      cumulative = 0.0
      rows = grid.map do |period|
        row = own[period.start_on]
        cumulative = row.cumulative_spent if row
        next CreditLedger::Row.new(**row.to_h.merge(period: period)) if row

        CreditLedger::Row.new(period: period, granted: 0.0, refilled: 0.0, spent: 0.0, credit_before: 0.0, balance: 0.0,
                              credit: 0.0, horizon: 0.0, cumulative_spent: cumulative)
      end
      CreditLedger.new(rows: rows, opening_balance: ledger ? ledger.opening_balance : 0.0)
    end

    def build(envelope, grid, opening)
      by_day = spent_days(envelope)
      monthly = grid.to_h do |month|
        [month.start_on, by_day.sum { |date, days| month.include?(date) ? days : 0.0 }]
      end
      CreditLedger.build(envelopes: [envelope], spent_days: monthly, months: grid, opening_balance: opening)
    end
  end
end
