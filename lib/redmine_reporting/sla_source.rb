# frozen_string_literal: true

module RedmineReporting
  # Read-only view of the redmine_sla plugin for a project. An SLA status is a status in
  # which the delay of an SLA type elapses: open statuses where no type of the project
  # elapses are waiting statuses (typically waiting for the requester).
  class SlaSource
    def initialize(project)
      @project = project
    end

    def installed?
      Redmine::Plugin.installed?(:redmine_sla) && defined?(::SlaProjectTracker) && defined?(::SlaStatus) ? true : false
    end

    def enabled?
      installed? && @project.module_enabled?(:sla) ? true : false
    end

    def configured?
      enabled? && project_trackers.exists?
    end

    # Why the SLA family is or is not available, as a translation key suffix.
    def state
      if configured? then "configured"
      elsif enabled? then "no_tracker"
      elsif installed? then "module_disabled"
      else "missing"
      end
    end

    # {SlaType => [IssueStatus]} for the SLA types used by the project's trackers.
    def active_statuses_by_type
      return {} unless configured?

      types = ::SlaType.where(id: project_trackers.joins(:sla_types).select("#{::SlaType.table_name}.id")).sorted
      statuses = ::SlaStatus.where(sla_type_id: types.map(&:id)).includes(:status).group_by(&:sla_type_id)
      types.to_h { |type| [type, Array(statuses[type.id]).map(&:status).sort_by(&:position)] }
    end

    def active_status_ids
      active_statuses_by_type.values.flatten.map(&:id).uniq
    end

    def waiting_status_ids
      IssueStatus.where(is_closed: false).where.not(id: active_status_ids).sorted.ids
    end

    private

    def project_trackers
      ::SlaProjectTracker.where(project_id: @project.id)
    end
  end
end
