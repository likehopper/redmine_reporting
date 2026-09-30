# frozen_string_literal: true

class ReportingSettingsController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize

  def update
    setting = ReportingProjectSetting.update_for(@project, setting_params)
    if setting.errors.empty?
      flash[:notice] = l(:notice_successful_update)
    else
      flash[:error] = setting.errors.full_messages.to_sentence
    end
    redirect_to settings_project_path(@project, tab: "reporting")
  end

  private

  def setting_params
    attributes = params.require(:reporting_setting).permit(:hours_per_day, section_ids: [], tracker_roles: {})
    if attributes[:tracker_roles]
      project_tracker_ids = @project.tracker_ids.map(&:to_s)
      attributes[:tracker_roles] = attributes[:tracker_roles].to_h.slice(*project_tracker_ids)
    end
    attributes
  end
end
