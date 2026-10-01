# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/sla_source.rb
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
