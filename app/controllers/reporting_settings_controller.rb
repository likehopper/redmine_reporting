# frozen_string_literal: true

class ReportingSettingsController < ApplicationController
  COPIED = %w[section_ids hours_per_day run_tracker_ids build_tracker_ids].freeze

  before_action :find_project_by_project_id
  before_action :authorize

  def update
    # Saving from a subproject that inherits its parent's settings creates its own configuration.
    setting = ReportingProjectSetting.find_or_initialize_by(project_id: @project.id)
    setting.assign_attributes(ReportingProjectSetting.for(@project).attributes.slice(*COPIED)) if setting.new_record?
    setting.assign_attributes(setting_params)
    if setting.save
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
