# frozen_string_literal: true

module RedmineReporting
  # What the project's Reporting settings tab shows. The tab is rendered by Redmine's
  # ProjectsController, so it reads everything from this object rather than from queries in the view.
  class ProjectSettings
    attr_reader :project

    def initialize(project)
      @project = project
    end

    def setting
      @setting ||= ReportingProjectSetting.for(project)
    end

    def inherited?
      setting.inherited_by?(project)
    end

    def sla
      @sla ||= SlaSource.new(project)
    end

    def sections
      Sections::ALL
    end

    def trackers
      @trackers ||= project.trackers.sorted.to_a
    end

    def policies
      @policies ||= project.reporting_credit_policies.sorted.includes(:tracker, :reporting_credit_refills).to_a
    end

    # Trackers that can still get a credit: one policy per tracker, the edited one excepted.
    def trackers_for_policy(policy = nil)
      taken = policies.reject { |item| item == policy }.map(&:tracker_id)
      trackers.reject { |tracker| taken.include?(tracker.id) }
    end

    def sla_waiting_statuses
      IssueStatus.where(id: sla.waiting_status_ids).sorted.to_a
    end
  end
end
