# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/credit_scope.rb
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
  # Which time entries each contract and envelope is charged with, as SQL conditions on the
  # time entries table, so they apply to any time entry scope. An hour goes to one envelope
  # at most:
  # 1. its issue's tracker and its date select the contract, the closest project winning;
  # 2. its activity and the issue's privacy select the envelope, listed activities first,
  #    then the contract's "other activities" envelope.
  # Time without an issue, or matching no envelope of its contract, is charged to none.
  # Conditions ignore issue visibility: credit is counted the same for every reader.
  class CreditScope
    attr_reader :contracts

    # Every contract that may cover the projects involved, with their subprojects' ones.
    def self.for_projects(projects)
      ids = projects.flat_map { |project| project.self_and_ancestors.pluck(:id) + project.descendants.pluck(:id) }.uniq
      new(ReportingCreditContract.where(project_id: ids).includes(:project, envelopes: :movements).to_a)
    end

    def initialize(contracts)
      @contracts = contracts
    end

    def contract_condition(contract)
      @contract_conditions ||= {}
      @contract_conditions[contract.id] ||= begin
        closer = closer_contracts(contract).filter_map { |other| coverage(other, contract) }
        [coverage(contract, contract), *closer.map { |condition| "NOT #{condition}" }].join(" AND ")
      end
    end

    def envelope_condition(envelope)
      contract = envelope.contract
      own = matching(envelope)
      return "(#{contract_condition(contract)} AND #{own})" unless envelope.other_activities

      listed = contract.live_envelopes.reject(&:other_activities).map { |other| matching(other) }
      "(#{[contract_condition(contract), own, *listed.map { |condition| "NOT #{condition}" }].join(' AND ')})"
    end

    # Time charged to any envelope of the contracts.
    def charged_condition(selected = contracts)
      conditions = selected.flat_map(&:live_envelopes).map { |envelope| envelope_condition(envelope) }
      conditions.empty? ? "1=0" : "(#{conditions.join(' OR ')})"
    end

    # Issues of the contract's projects and trackers, of a privacy one of its envelopes takes,
    # without the trackers a closer contract covers at some point.
    def issue_condition(contract)
      privacies = contract.live_envelopes.map(&:issue_privacy).uniq
      privacy = if privacies.include?("all") || privacies.sort == %w[private public] then nil
                elsif privacies == ["private"] then true
                elsif privacies == ["public"] then false
                end
      conditions = [issue_coverage(contract, contract.tracker_ids)]
      conditions << sanitize("#{Issue.table_name}.is_private = ?", privacy) unless privacy.nil?
      closer_contracts(contract).each do |other|
        shared = other.tracker_ids & contract.tracker_ids
        conditions << "NOT #{issue_coverage(other, shared)}" if shared.any? && other.overlaps?(contract)
      end
      conditions << "1=0" if privacies.empty?
      "(#{conditions.join(' AND ')})"
    end

    def project_ids(contract)
      @project_ids ||= {}
      @project_ids[contract.id] ||= contract.include_subprojects ? contract.project.self_and_descendants.pluck(:id) : [contract.project_id]
    end

    private

    # Contracts of strictly lower projects in the contract's reach: they take its time.
    def closer_contracts(contract)
      return [] unless contract.include_subprojects

      reach = project_ids(contract) - [contract.project_id]
      contracts.select { |other| other.id != contract.id && reach.include?(other.project_id) }
    end

    # Time of the contract's projects, on its trackers and dates, within the limits of another
    # one when given (the shared trackers and dates); nil when they share nothing.
    def coverage(contract, within)
      trackers = contract.tracker_ids & within.tracker_ids
      first_day = [contract.starts_on, within.starts_on].max
      last_day = [contract.ends_on, within.ends_on].min
      return if trackers.empty? || first_day > last_day

      sanitize(
        "(#{TimeEntry.table_name}.project_id IN (?) AND #{TimeEntry.table_name}.spent_on BETWEEN ? AND ? AND " \
        "EXISTS (SELECT 1 FROM #{Issue.table_name} reporting_credit_issues WHERE reporting_credit_issues.id = " \
        "#{TimeEntry.table_name}.issue_id AND reporting_credit_issues.tracker_id IN (?)))",
        project_ids(contract), first_day, last_day, trackers
      )
    end

    def issue_coverage(contract, tracker_ids)
      sanitize("(#{Issue.table_name}.project_id IN (?) AND #{Issue.table_name}.tracker_id IN (?))", project_ids(contract), tracker_ids)
    end

    # The envelope's own criteria: activities (project-specific copies included) and privacy.
    def matching(envelope)
      conditions = []
      unless envelope.other_activities
        ids = envelope.activity_ids + TimeEntryActivity.where(parent_id: envelope.activity_ids).pluck(:id)
        conditions << sanitize("#{TimeEntry.table_name}.activity_id IN (?)", ids)
      end
      if envelope.issue_privacy != "all"
        conditions << sanitize(
          "EXISTS (SELECT 1 FROM #{Issue.table_name} reporting_credit_private WHERE reporting_credit_private.id = " \
          "#{TimeEntry.table_name}.issue_id AND reporting_credit_private.is_private = ?)",
          envelope.issue_privacy == "private"
        )
      end
      conditions.empty? ? "1=1" : "(#{conditions.join(' AND ')})"
    end

    def sanitize(*arguments)
      ActiveRecord::Base.send(:sanitize_sql_array, arguments)
    end
  end
end
