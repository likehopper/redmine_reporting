# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/project_settings.rb
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
