# frozen_string_literal: true

module RedmineReporting
  class SpentTime
    def initialize(time_entry_scope, issue_ids)
      @days = Hash.new { |hash, issue_id| hash[issue_id] = [] }
      time_entry_scope.where(issue_id: issue_ids).group(:issue_id, :spent_on).sum(:hours).
        each { |(issue_id, spent_on), hours| @days[issue_id] << [spent_on, hours.to_f] }
      @days.each_value do |entries|
        total = 0.0
        entries.sort_by!(&:first)
        entries.map! { |day, hours| [day, total += hours] }
      end
    end

    def total(issue)
      @days.fetch(issue.id, []).last&.last || 0.0
    end

    def until(issue, date)
      entries = @days.fetch(issue.id, [])
      index = entries.bsearch_index { |day, _| day > date } || entries.length
      index.zero? ? 0.0 : entries[index - 1].last
    end
  end
end
