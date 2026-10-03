# frozen_string_literal: true
# File: redmine_reporting/app/controllers/reporting_controller.rb
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

class ReportingController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_reporting_setting
  before_action :build_reporting_query

  helper :queries
  helper :reporting

  def index
    section = RedmineReporting::Sections.find(@query.section)
    @capabilities = RedmineReporting::Capabilities.new(User.current, @query.visible_projects)
    @disabled_reason =
      if RedmineReporting::Sections.visible(@project, User.current, @reporting_setting).exclude?(section) then "sections"
      elsif @capabilities.tabs(section).empty? then "modules"
      end
    return render(:disabled) if @disabled_reason

    @tabs = @capabilities.tabs(section)
    @active_tab = @tabs.include?(params[:tab]) ? params[:tab] : @tabs.first
    grid = RedmineReporting::PeriodGrid.from_params(from: params[:from], to: params[:to], grouping: params[:grouping], today: User.current.today)
    @date_from, @date_to, @grouping = grid.first_day, grid.last_day, grid.grouping
    @report_query_params = @query.as_params.merge(grouping: @grouping)
    @report_data = RedmineReporting::ReportBuilder.new(query: @query, first_day: @date_from, last_day: @date_to,
                                                      grouping: @grouping, hours_per_day: @reporting_setting.hours_per_day).build
    @dashboard = RedmineReporting::DashboardPresenter.new(view: view_context, query: @query, grid: grid,
      report: @report_data, hours_per_day: @reporting_setting.hours_per_day)
  rescue RedmineReporting::PeriodGrid::InvalidRange
    flash.now[:error] = l(:label_reporting_invalid_range, count: RedmineReporting::PeriodGrid::MAX_PERIODS)
    render :invalid, status: :unprocessable_entity
  end

  def details
    drilldown = RedmineReporting::Drilldown.build(@query, params)
    redirect_to drilldown.path
  end

  private

  def load_reporting_setting
    @reporting_setting = ReportingProjectSetting.for(@project)
  end

  def build_reporting_query
    @query = ReportingQuery.new(name: "Reporting", project: @project, user: User.current)
    visible_sections = RedmineReporting::Sections.visible(@project, User.current, @reporting_setting)
    @query.section = params[:section].present? ? (params[:section] == "build" ? "build" : "run") : (visible_sections.first&.id || "run")
    @query.run_tracker_ids = @query.section == "build" ? @reporting_setting.build_tracker_ids : @reporting_setting.run_scope_tracker_ids
    @query.build_from_params(params)
  end
end
