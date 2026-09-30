# frozen_string_literal: true

class ReportingController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_reporting_setting
  before_action :build_reporting_query

  helper :queries
  helper :reporting

  def index
    run = RedmineReporting::Sections.find("run")
    @capabilities = RedmineReporting::Capabilities.new(User.current, @query.visible_projects)
    @disabled_reason =
      if RedmineReporting::Sections.visible(@project, User.current, @reporting_setting).exclude?(run) then "sections"
      elsif !@capabilities.any? then "modules"
      end
    return render(:disabled) if @disabled_reason

    @tabs = @capabilities.tabs(run)
    @active_tab = @tabs.include?(params[:tab]) ? params[:tab] : @tabs.first
    grid = RedmineReporting::PeriodGrid.from_params(from: params[:from], to: params[:to], grouping: params[:grouping], today: User.current.today)
    @date_from, @date_to, @grouping = grid.first_day, grid.last_day, grid.grouping
    @report_query_params = @query.as_params.merge(grouping: @grouping)
    @report_data = RedmineReporting::ReportBuilder.new(query: @query, first_day: @date_from, last_day: @date_to,
                                                      grouping: @grouping, hours_per_day: @reporting_setting.hours_per_day).build
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
    @query.run_tracker_ids = @reporting_setting.run_scope_tracker_ids
    @query.build_from_params(params)
  end
end
