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
    # Dates follow the viewer's time zone, as Redmine's own date filters do.
    @date_to = parse_date(params[:to]) || User.current.today
    @date_from = parse_date(params[:from]) || (@date_to << 11).beginning_of_month
    @date_from, @date_to = [@date_from, @date_to].minmax
    @grouping = RedmineReporting::PeriodGrid::GROUPINGS.include?(params[:grouping]) ? params[:grouping] : "month"
    @report_query_params = @query.as_params.merge(grouping: @grouping)
    @report_data = RedmineReporting::ReportBuilder.new(query: @query, first_day: @date_from, last_day: @date_to,
                                                      grouping: @grouping, hours_per_day: @reporting_setting.hours_per_day).build
  end

  def details
    drilldown = RedmineReporting::Drilldown.build(@query, params)
    redirect_to drilldown.path
  end

  private

  def parse_date(value)
    Date.parse(value.to_s) if value.present?
  rescue Date::Error
    nil
  end

  def load_reporting_setting
    @reporting_setting = ReportingProjectSetting.for(@project)
  end

  def build_reporting_query
    @query = ReportingQuery.new(name: "Reporting", project: @project, user: User.current)
    @query.run_tracker_ids = @reporting_setting.run_scope_tracker_ids
    @query.build_from_params(params)
  end
end
