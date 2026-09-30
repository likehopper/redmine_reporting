# frozen_string_literal: true

module RedmineReporting
  # Records a report reads, loaded once per request from the reporting query: issue
  # timelines, time entries of the period, spent time per issue and the credit policies of
  # every project in scope (subprojects included).
  class ReportData
    attr_reader :query, :user, :grid, :hours_per_day

    def initialize(query:, first_day:, last_day:, grouping:, hours_per_day:)
      @query = query
      @user = query.user || User.current
      @grid = PeriodGrid.new(first_day, last_day, grouping)
      @hours_per_day = hours_per_day.to_f.positive? ? hours_per_day.to_f : ReportingProjectSetting::DEFAULT_HOURS_PER_DAY
    end

    delegate :first_day, :last_day, to: :grid

    def timelines
      @timelines ||= issues.map { |issue| IssueTimeline.new(issue, user) }
    end

    def time_entries
      @time_entries ||= query.time_entry_scope.where(spent_on: first_day..last_day).includes(:user, :activity).to_a
    end

    def spent_time
      @spent_time ||= SpentTime.new(query.time_entry_scope, issues.map(&:id))
    end

    def policies
      @policies ||= begin
        scope = ReportingCreditPolicy.active.where(project_id: projects.map(&:id))
        scope = scope.where(tracker_id: query.selected_tracker_ids) if query.tracker_restricted?
        scope.includes(:reporting_credit_refills).to_a
      end
    end

    def projects
      @projects ||= query.selected_projects.to_a
    end

    # Consumed days per project and month over a month grid: {[project_id, month start] => days}.
    def spent_days_by_project_and_month(months)
      query.time_entry_scope.where(spent_on: months.first_day..months.last_day).group(:project_id, :spent_on).sum(:hours).
        each_with_object(Hash.new(0.0)) do |((project_id, spent_on), hours), totals|
          totals[[project_id, spent_on.beginning_of_month]] += days(hours)
        end
    end

    def days(hours)
      hours.to_f / hours_per_day
    end

    private

    # Issues closed before the period cannot appear in any chart; open ones always can.
    def issues
      @issues ||= begin
        scope = query.issue_scope
        scope = scope.where(closed_on: nil).
          or(scope.where(closed_on: (first_day - 1).beginning_of_day..)).
          or(scope.where(status_id: IssueStatus.where(is_closed: false).select(:id)))
        scope.includes(:tracker, :status, :priority).to_a
      end
    end
  end
end
