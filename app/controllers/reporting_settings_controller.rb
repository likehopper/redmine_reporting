# frozen_string_literal: true
# File: redmine_reporting/app/controllers/reporting_settings_controller.rb
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
