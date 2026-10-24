# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/report_data.rb
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
  # Records a report reads, loaded once per request from the reporting query: issue
  # timelines, time entries of the period, spent time per issue and the credit contracts
  # of the projects in scope (subprojects included).
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

    # Contracts of the projects whose credit the user may read, as selected by the contract
    # filter. A contract's figures cover its whole reach, whatever the other filters.
    def contracts
      @contracts ||= begin
        list = query.contract_filter_owned.select { |contract| credit_projects.include?(contract.project) }
        if query.has_filter?("reporting_contract")
          ids = query.values_for("reporting_contract").map(&:to_s)
          list = list.select { |contract| ids.include?(contract.id.to_s) == (query.operator_for("reporting_contract") == "=") }
        end
        list
      end
    end

    def contract_account(contract)
      @contract_accounts ||= {}
      @contract_accounts[contract.id] ||= CreditContractAccount.new(contract, scope: query.contract_filter_scope,
                                                                    hours: contract_hours, default_hours: hours_per_day)
    end

    def credit_projects
      @credit_projects ||= projects.select { |project| user.allowed_to?(:view_time_entries, project) && user.allowed_to?(:view_reporting, project) }
    end

    def projects
      @projects ||= query.selected_projects.to_a
    end

    def project_hours
      @project_hours ||= ReportingProjectSetting.hours_by_project(projects, hours_per_day)
    end

    # Days of the reported time, charged to no contract or to an ancestor's, over a range.
    def unchargeable_days(bucket, first_day, last_day)
      condition = query.contract_filter_condition("reporting_contract", "=", [bucket], :time_entries)
      query.time_entry_scope.where(spent_on: first_day..last_day).where(condition).group(:project_id).sum(:hours).
        sum { |project_id, hours| hours.to_f / project_hours.fetch(project_id, hours_per_day) }
    end

    def days(hours)
      hours.to_f / hours_per_day
    end

    private

    # Hours per day of every project a contract may cover, invisible subprojects included.
    def contract_hours
      @contract_hours ||= begin
        scope = query.contract_filter_scope
        ids = scope.contracts.flat_map { |contract| scope.project_ids(contract) }.uniq
        ReportingProjectSetting.hours_by_project(Project.where(id: ids).to_a, hours_per_day)
      end
    end

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
