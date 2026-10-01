# frozen_string_literal: true

module RedmineReporting
  # Records a report reads, loaded once per request from the reporting query: issue
  # timelines, time entries of the period, spent time per issue and the credit policies of
  # every project in scope (subprojects included).
  class ReportData
    attr_reader :query, :user, :grid, :hours_per_day, :capabilities

    def initialize(query:, first_day:, last_day:, grouping:, hours_per_day:)
      @query = query
      @user = query.user || User.current
      @capabilities = Capabilities.new(@user, query.visible_projects)
      @grid = PeriodGrid.new(first_day, last_day, grouping)
      @hours_per_day = hours_per_day.to_f.positive? ? hours_per_day.to_f : ReportingProjectSetting::DEFAULT_HOURS_PER_DAY
    end

    delegate :first_day, :last_day, to: :grid

    def timelines
      @timelines ||= begin
        statuses = IssueStatus.all.to_a
        closed_ids = statuses.select(&:is_closed).map(&:id)
        events = JournalDetail.joins(:journal).where(property: "attr", prop_key: "status_id",
          journals: {journalized_type: "Issue", journalized_id: issues.map(&:id)}).
          order("journals.created_on", "journals.id", "journal_details.id").
          pluck("journals.journalized_id", "journals.created_on", :old_value, :value).group_by(&:first)
        issues.map do |issue|
          history = IssueHistory.new(issue, user, Array(events[issue.id]).map { |row| row.drop(1) }, closed_ids, statuses.map(&:id))
          IssueTimeline.new(issue, user, history: history)
        end
      end
    end

    def time_entries
      @time_entries ||= query.time_entry_scope.where(spent_on: first_day..last_day).includes(:user, :activity).to_a
    end

    def spent_time
      @spent_time ||= SpentTime.new(query.time_entry_scope, issues.map(&:id))
    end

    def policies
      @policies ||= begin
        scope = ReportingCreditPolicy.active.where(project_id: credit_projects.map(&:id))
        scope = scope.where(tracker_id: query.selected_tracker_ids) if query.tracker_restricted?
        scope.includes(:reporting_credit_refills).to_a
      end
    end

    def credit_projects
      @credit_projects ||= projects.select { |project| user.allowed_to?(:view_time_entries, project) && user.allowed_to?(:view_reporting, project) }
    end

    def projects
      @projects ||= query.selected_projects.to_a
    end

    # Days logged per project and month between two dates, each project at its own hours
    # per day: {[project_id, month start] => days}.
    def spent_days_by_project_and_month(first_day, last_day)
      (@spent_days ||= {})[[first_day, last_day]] ||=
        query.time_entry_scope.where(project_id: credit_projects.map(&:id), spent_on: first_day..last_day).
          group(:project_id, :spent_on).sum(:hours).
          each_with_object(Hash.new(0.0)) do |((project_id, spent_on), hours), totals|
            totals[[project_id, spent_on.beginning_of_month]] += hours.to_f / project_hours.fetch(project_id, hours_per_day)
          end
    end

    def project_hours
      @project_hours ||= begin
        settings = ReportingProjectSetting.joins(:project).order("projects.lft DESC").includes(:project).to_a
        projects.to_h do |project|
          inherited = settings.find { |setting| setting.project.lft <= project.lft && setting.project.rgt >= project.rgt }
          [project.id, inherited ? inherited.hours_per_day.to_f : hours_per_day]
        end
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
