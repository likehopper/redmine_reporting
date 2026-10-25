# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/contract_filters.rb
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
  # "Contract" and "Private issue" filters, shared by the reporting query and Redmine's issue
  # and time entry lists, so chart clicks open exactly what the report counts. Contract values
  # are contract IDs, "none" (charged to no contract) and "parent" (charged to a contract of
  # an ancestor project). Time entries follow the exact charging rules; issues follow their
  # contract's projects, trackers and privacy, whatever the dates.
  module ContractFilters
    NONE = "none"
    PARENT = "parent"

    def add_contract_filters
      add_available_filter "reporting_contract", type: :list, name: l(:label_reporting_contract),
        values: -> { contract_filter_values }
      add_available_filter "reporting_private", type: :list, name: l(:label_reporting_private),
        values: -> { [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]] }
    end

    def sql_for_reporting_contract_field(field, operator, values)
      contract_filter_condition(field, operator, values, contract_filter_records)
    end

    def sql_for_reporting_private_field(field, operator, values)
      contract_filter_condition(field, operator, values, contract_filter_records)
    end

    # The filter's condition on issues or on time entries.
    def contract_filter_condition(field, operator, values, records)
      if field == "reporting_contract"
        condition = contract_selection_condition(values, records)
        return operator == "!" ? "NOT #{condition}" : condition
      end

      selected = values.map(&:to_s)
      return "1=1" if selected.sort == %w[0 1]
      return "1=0" if selected.empty?

      private_only = (selected == ["1"]) == (operator == "=")
      if records == :time_entries
        exists = "EXISTS (SELECT 1 FROM #{Issue.table_name} reporting_private_issues WHERE reporting_private_issues.id = " \
                 "#{TimeEntry.table_name}.issue_id AND reporting_private_issues.is_private = #{self.class.connection.quoted_true})"
        private_only ? exists : "NOT #{exists}"
      else
        "#{Issue.table_name}.is_private = #{private_only ? self.class.connection.quoted_true : self.class.connection.quoted_false}"
      end
    end

    # Contracts the filter offers: those of the project and its subprojects, then the time
    # covered by an ancestor's contract, then the time no contract takes.
    def contract_filter_values
      values = contract_filter_owned.map { |contract| [contract_filter_label(contract), contract.id.to_s] }
      values << [l(:label_reporting_contract_parent), PARENT] if contract_filter_parents.any?
      values << [l(:label_reporting_contract_none), NONE]
    end

    def contract_filter_owned
      projects = contract_filter_projects
      contract_filter_scope.contracts.select { |contract| projects.include?(contract.project) }.
        sort_by { |contract| [contract.project.lft, contract.starts_on, contract.id] }
    end

    # Ancestors' contracts reaching the project.
    def contract_filter_parents
      return [] unless project

      ancestor_ids = project.ancestors.pluck(:id)
      contract_filter_scope.contracts.select { |contract| contract.include_subprojects && ancestor_ids.include?(contract.project_id) }
    end

    def contract_filter_scope
      @contract_filter_scope ||=
        if project then CreditScope.for_projects([project])
        else CreditScope.new(ReportingCreditContract.where(project_id: Project.allowed_to(:view_reporting).select(:id)).
                               includes(:project, envelopes: :movements).to_a)
        end
    end

    private

    # Projects whose contracts the user may name: visible, with the permission to view reporting.
    def contract_filter_projects
      reader = (respond_to?(:user) && user) || User.current
      projects = project ? project.self_and_descendants.to_a : contract_filter_scope.contracts.map(&:project).uniq
      projects.select { |item| reader.allowed_to?(:view_reporting, item) }
    end

    def contract_filter_label(contract)
      contract.project == project ? contract.name : "#{contract.project.name} · #{contract.name}"
    end

    def contract_filter_records
      queried_class == TimeEntry ? :time_entries : :issues
    end

    def contract_selection_condition(values, records)
      scope = contract_filter_scope
      ids = values.map(&:to_s)
      selected = scope.contracts.select { |contract| ids.include?(contract.id.to_s) }
      selected |= contract_filter_parents if ids.include?(PARENT)
      conditions = selected.map { |contract| contract_condition(scope, contract, records) }
      if ids.include?(NONE)
        any = scope.contracts.map { |contract| contract_condition(scope, contract, records) }
        conditions << (any.empty? ? "1=1" : "NOT (#{any.join(' OR ')})")
      end
      conditions.empty? ? "1=0" : "(#{conditions.join(' OR ')})"
    end

    def contract_condition(scope, contract, records)
      records == :time_entries ? scope.charged_condition([contract]) : scope.issue_condition(contract)
    end
  end
end
