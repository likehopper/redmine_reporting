# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/consumption.rb
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
    # What the client had, consumed and has left, over the selected period and over the
    # contracts, contract by contract and envelope by envelope. Contracts add up month by
    # month: each one starts from its own credit and stops at its end, so an overrun on one
    # never eats another one's credit. Time no contract takes is shown apart.
    class Consumption < Base
      def to_h
        period = ledger(period_months)
        {
          period: series(period).merge(totals: totals(period), outside: bucket_days(ContractFilters::NONE),
                                       parent: bucket_days(ContractFilters::PARENT)),
          contract: series(ledger(contract_months)),
          contracts: contracts.filter_map { |contract| contract_row(contract) }
        }
      end

      private

      def contracts
        data.contracts
      end

      def period_months
        @period_months ||= PeriodGrid.new(first_day, last_day, "month")
      end

      # From the earliest contract start, or the period start without contracts.
      def contract_months
        start = contracts.map(&:starts_on).min
        PeriodGrid.new(start ? [start, last_day].min : first_day, last_day, "month")
      end

      def ledger(grid)
        return CreditLedger.build(envelopes: [], spent_days: {}, months: grid) if contracts.empty?

        CreditLedger.sum(contracts.map { |contract| data.contract_account(contract).ledger_on(grid) })
      end

      # Time outside contracts or covered by a parent's, when the selection shows it.
      def bucket_days(bucket)
        return if bucket == ContractFilters::PARENT && data.query.contract_filter_parents.empty?
        return unless bucket_selected?(bucket)

        round(data.unchargeable_days(bucket, first_day, last_day))
      end

      def bucket_selected?(bucket)
        query = data.query
        return true unless query.has_filter?("reporting_contract")

        query.values_for("reporting_contract").include?(bucket) == (query.operator_for("reporting_contract") == "=")
      end

      def totals(ledger)
        {opening: round(ledger.opening_balance), granted: round(ledger.granted), available: round(ledger.available),
         consumed: round(ledger.consumed), remaining: round(ledger.remaining), progress: ledger.progress}
      end

      # Only contracts running at some point of the period.
      def contract_row(contract)
        account = data.contract_account(contract)
        ledger = account.ledger(first_day, last_day)
        return unless ledger

        project = contract.project
        envelopes = account.envelopes.filter_map do |envelope|
          envelope_ledger = account.envelope_ledger(envelope, first_day, last_day)
          {name: envelope.name, **totals(envelope_ledger), **closing(account, envelope)}
        end
        {id: contract.id, name: contract.name, project: project.name, identifier: project.identifier,
         own: project == data.query.project, from: contract.starts_on.iso8601, to: contract.ends_on.iso8601,
         ended: contract.ends_on <= last_day, **totals(ledger),
         closing: round(envelopes.sum { |envelope| envelope[:closing] || 0 }),
         carried: round(envelopes.sum { |envelope| envelope[:carried] || 0 }), envelopes: envelopes}
      end

      # Balance left on the contract's last day, and what the next contract took over.
      def closing(account, envelope)
        return {} unless account.contract.ends_on <= last_day

        {closing: round(account.closing_balance(envelope)), carried: round(account.carried_out(envelope))}
      end

      def series(ledger)
        rows = ledger.rows
        {
          labels: rows.map { |row| row.period.label },
          periodStarts: rows.map { |row| row.period.start },
          periodRanges: rows.map { |row| {from: row.period.first_day.iso8601, to: row.period.last_day.iso8601} },
          contractIds: contracts.map(&:id),
          spent: rows.map { |row| round(row.spent) },
          refills: rows.map { |row| round(row.refilled) },
          grants: rows.map { |row| round(row.granted) },
          creditBefore: rows.map { |row| round(row.credit_before) },
          credit: rows.map { |row| round(row.credit) },
          horizon: rows.map { |row| round(row.horizon) },
          cumulativeSpent: rows.map { |row| round(row.cumulative_spent) }
        }
      end
    end
  end
end
