# frozen_string_literal: true

module RedmineReporting
  # The credits of a set of projects and the time charged to them. Credit starts on the
  # earliest policy start: time logged before it is not charged. Any period is read from
  # the balance carried over to its first day, so a July-December report of a 10-day
  # yearly contract with 3 days used in the first half starts with 7 days.
  class CreditAccount
    attr_reader :project, :project_ids, :policies

    def initialize(project:, project_ids:, policies:, data:)
      @project = project
      @project_ids = project_ids
      @policies = policies
      @data = data
    end

    def start
      @start ||= policies.filter_map(&:active_from).min
    end

    def ledger(months)
      # A displayed subtree is a sum of project accounts, never a shared balance.
      # This keeps debt and contract start dates independent at every tree depth.
      return CreditLedger.sum(project_accounts.map { |account| account.ledger(months) }) if project_ids.length > 1

      CreditLedger.build(policies: policies, spent_days: charged_days(months.first_day, months.last_day), months: months,
                         opening_balance: opening_balance(months.first_day))
    end

    private

    def project_accounts
      @project_accounts ||= begin
        projects_by_id = @data.projects.index_by(&:id)
        project_ids.map do |project_id|
          self.class.new(project: projects_by_id.fetch(project_id), project_ids: [project_id], data: @data,
                         policies: policies.select { |policy| policy.project_id == project_id })
        end
      end
    end

    def opening_balance(date)
      return 0.0 unless start && start < date

      history = PeriodGrid.new(start, date - 1, "month")
      CreditLedger.build(policies: policies, spent_days: charged_days(start, date - 1), months: history).closing_balance
    end

    # Charged days per month start between two dates, from the credit start on.
    def charged_days(first_day, last_day)
      first_day = [first_day, start].max if start
      return {} if first_day > last_day

      @data.spent_days_by_project_and_month(first_day, last_day).each_with_object(Hash.new(0.0)) do |((project_id, month), days), totals|
        totals[month] += days if project_ids.include?(project_id)
      end
    end
  end
end
