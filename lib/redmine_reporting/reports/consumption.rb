# frozen_string_literal: true

module RedmineReporting
  module Reports
    # Credits of every project in scope against the time logged, over the last 12 months and
    # over the contract, with one row per subproject so each one can be checked.
    class Consumption < Base
      def to_h
        last12 = PeriodGrid.months(last_day.beginning_of_month << 11, last_day)
        contract = PeriodGrid.months(contract_start || last12.first_day, last_day)

        rows = ledger(contract).rows
        prefix = last12.first_day < contract.first_day ? ledger(last12).rows.select { |row| row.period.first_day < contract.first_day } : []
        {
          last12: series(prefix + rows.select { |row| row.period.first_day >= last12.first_day }),
          contract: series(rows.select { |row| row.period.first_day >= contract.first_day }),
          initialCredit: round(policies.sum { |policy| policy.initial_credit_days.to_f }),
          projects: branches.filter_map { |project, project_ids| branch_row(project, project_ids, contract) }
        }
      end

      private

      def contract_start
        policies.filter_map(&:active_from).min&.beginning_of_month&.then { |start| [start, last_day.beginning_of_month].min }
      end

      def ledger(months, project_ids = nil)
        spent = Hash.new(0.0)
        spent_by_project(months).each do |(project_id, month), days|
          spent[month] += days if project_ids.nil? || project_ids.include?(project_id)
        end
        scoped = project_ids ? policies.select { |policy| project_ids.include?(policy.project_id) } : policies
        CreditLedger.new(policies: scoped, spent_days: spent, months: months)
      end

      def spent_by_project(months)
        (@spent_by_project ||= {})[months.first_day] ||= data.spent_days_by_project_and_month(months)
      end

      def series(rows)
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

      # The reporting project for its own time and credits, then each direct subproject with
      # its whole subtree, as its own reporting page shows it. Only listed with subprojects.
      def branches
        projects = data.credit_projects
        root = data.query.project
        return [] unless root && projects.length > 1

        branches = projects.include?(root) ? [[root, [root.id]]] : []
        root.children.visible(data.user).sort_by(&:lft).each do |child|
          ids = projects.select { |project| project.lft >= child.lft && project.rgt <= child.rgt }.map(&:id)
          branches << [child, ids] if ids.any?
        end
        branches
      end

      def branch_row(project, project_ids, contract)
        ledger = ledger(contract, project_ids)
        return if ledger.available.zero? && ledger.consumed.zero?

        {
          id: project.id, identifier: project.identifier, name: project.name, own: project == data.query.project,
          granted: round(ledger.granted), refilled: round(ledger.refilled), consumed: round(ledger.consumed),
          remaining: round(ledger.remaining), progress: ledger.progress
        }
      end
    end
  end
end
