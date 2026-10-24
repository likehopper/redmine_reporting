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
    # Vertical sub-tabs of the settings tab, each with its own form, in display order.
    PANES = %w[sections time_unit trackers sla_statuses contracts].freeze

    attr_reader :project

    # Unknown or unavailable panes fall back to the first one.
    def self.pane_param(pane)
      PANES.include?(pane.to_s) ? pane.to_s : nil
    end

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

    # SLA statuses are read from the SLA plugin and only shown when it is configured.
    def panes
      PANES.select { |pane| pane != "sla_statuses" || sla.configured? }
    end

    def pane(requested)
      panes.include?(requested.to_s) ? requested.to_s : panes.first
    end

    def trackers
      @trackers ||= project.trackers.sorted.to_a
    end

    def contracts
      @contracts ||= project.reporting_credit_contracts.sorted.includes(envelopes: [:movements, :carried_movements]).to_a
    end

    # Current contracts first, then upcoming and finished ones.
    def contracts_by_status(today)
      groups = contracts.group_by { |contract| contract.status(today) }
      %w[current upcoming finished].filter_map { |status| [status, groups[status]] if groups[status] }
    end

    # Trackers a contract may cover: the project's and its subprojects'.
    def contract_trackers
      @contract_trackers ||= project.rolled_up_trackers.sorted.to_a
    end

    # Active shared activities, and the given ones even inactive: a project-specific activity
    # counts as the shared activity it overrides.
    def activities(selected_ids = [])
      TimeEntryActivity.shared.where(active: true).or(TimeEntryActivity.shared.where(id: selected_ids)).sorted.to_a
    end

    def account(contract)
      @accounts ||= {}
      @accounts[contract.id] ||= CreditContractAccount.new(contract, scope: credit_scope, hours: hours_by_project)
    end

    # Consumed and remaining days up to today, within the contract.
    def usage(contract, today)
      ledger = account(contract).ledger(contract.starts_on, [today, contract.ends_on].min) if today >= contract.starts_on
      ledger ? {consumed: ledger.consumed, remaining: ledger.closing_balance} : {consumed: 0.0, remaining: contract.days}
    end

    # What is left to carry over from an envelope: its closing balance less what was carried already.
    def carry_over(envelope)
      account(envelope.contract).closing_balance(envelope) - account(envelope.contract).carried_out(envelope)
    end

    # Subprojects' contracts that take this contract's time on some trackers and dates.
    def closer_contracts(contract)
      return [] unless contract.include_subprojects && contract.starts_on && contract.ends_on

      ReportingCreditContract.where(project_id: project.descendants.select(:id)).includes(:project).select do |other|
        other.overlaps?(contract) && (other.tracker_ids & contract.tracker_ids).any?
      end
    end

    def sla_waiting_statuses
      IssueStatus.where(id: sla.waiting_status_ids).sorted.to_a
    end

    private

    def credit_scope
      @credit_scope ||= CreditScope.for_projects([project])
    end

    def hours_by_project
      @hours_by_project ||= ReportingProjectSetting.hours_by_project(project.self_and_descendants.to_a, setting.hours_per_day)
    end
  end
end
