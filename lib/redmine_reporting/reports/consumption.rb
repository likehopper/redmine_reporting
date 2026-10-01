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
    # contract. Each subproject is an account of its own; the project's figures add them up,
    # so its summary rows and each subproject's own report agree.
    class Consumption < Base
      def to_h
        period = CreditLedger.sum(accounts.map { |account| account.ledger(period_months) })
        {
          period: series(period).merge(totals: totals(period)),
          contract: series(CreditLedger.sum(accounts.map { |account| account.ledger(contract_months) })),
          projects: accounts.length > 1 ? accounts.filter_map { |account| account_row(account) } : []
        }
      end

      private

      def period_months
        @period_months ||= PeriodGrid.new(first_day, last_day, "month")
      end

      # From the earliest credit start, or the period start when no credit applies.
      def contract_months
        start = accounts.filter_map(&:start).min
        PeriodGrid.new(start ? [start, last_day].min : first_day, last_day, "month")
      end

      # The displayed project for its own credits and time, then each direct subproject with
      # its whole subtree; a single account when there is nothing to break down.
      def accounts
        @accounts ||= begin
          projects = data.credit_projects
          root = data.query.project
          branches = branches(root, projects)
          branches = [[root, projects.map(&:id)]] if branches.length < 2
          branches.map do |project, ids|
            CreditAccount.new(project: project, project_ids: ids, data: data,
                              policies: policies.select { |policy| ids.include?(policy.project_id) })
          end
        end
      end

      def branches(root, projects)
        return [] unless root && projects.length > 1

        list = projects.include?(root) ? [[root, [root.id]]] : []
        root.children.visible(data.user).sort_by(&:lft).each do |child|
          ids = projects.select { |project| project.lft >= child.lft && project.rgt <= child.rgt }.map(&:id)
          list << [child, ids] if ids.any?
        end
        list
      end

      def totals(ledger)
        {opening: round(ledger.opening_balance), granted: round(ledger.granted), available: round(ledger.available),
         consumed: round(ledger.consumed), remaining: round(ledger.remaining), progress: ledger.progress}
      end

      def account_row(account)
        ledger = account.ledger(period_months)
        return if ledger.available.zero? && ledger.consumed.zero? && ledger.opening_balance.zero?

        project = account.project
        {id: project.id, identifier: project.identifier, name: project.name, own: project == data.query.project,
         **totals(ledger)}
      end

      def series(ledger)
        rows = ledger.rows
        {
          labels: rows.map { |row| row.period.label },
          periodStarts: rows.map { |row| row.period.start },
          periodRanges: rows.map { |row| {from: row.period.first_day.iso8601, to: row.period.last_day.iso8601} },
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
