# frozen_string_literal: true

module RedmineReporting
  # Visible hours per issue and day, so remaining time can also be computed at a past date.
  class SpentTime
    def initialize(time_entry_scope, issue_ids)
      @days = Hash.new { |hash, issue_id| hash[issue_id] = [] }
      time_entry_scope.where(issue_id: issue_ids).group(:issue_id, :spent_on).sum(:hours).
        each { |(issue_id, spent_on), hours| @days[issue_id] << [spent_on, hours.to_f] }
    end

    def total(issue)
      @days.fetch(issue.id, []).sum(&:last)
    end

    def until(issue, date)
      @days.fetch(issue.id, []).sum { |spent_on, hours| spent_on <= date ? hours : 0.0 }
    end
  end
end
