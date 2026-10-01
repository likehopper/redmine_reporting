# frozen_string_literal: true
# File: redmine_reporting/app/controllers/reporting_credit_policies_controller.rb
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

class ReportingCreditPoliciesController < ApplicationController
  menu_item :settings
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_policy, only: [:edit, :update, :destroy]
  before_action :load_settings_page

  helper :reporting

  def new
    tracker = @settings_page.trackers_for_policy.first
    @policy = @project.reporting_credit_policies.build(tracker: tracker, name: tracker&.name, anniversary_month: 1,
                                                       anniversary_day: 1, active_from: User.current.today.beginning_of_year)
  end

  def create
    @policy = @project.reporting_credit_policies.build(policy_params)
    if @policy.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to_settings
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @policy.update(policy_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to_settings
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @policy.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_settings
  end

  private

  def find_policy
    @policy = @project.reporting_credit_policies.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def load_settings_page
    @settings_page = RedmineReporting::ProjectSettings.new(@project)
  end

  def policy_params
    attributes = params.require(:reporting_credit_policy).permit(
      :tracker_id, :name, :initial_credit_days, :anniversary_month, :anniversary_day, :active_from, :active_until, :enabled,
      reporting_credit_refills_attributes: [:id, :month, :day, :credit_days, :starts_on, :ends_on, :_destroy]
    )
    # A policy only covers one of the project's trackers.
    attributes.delete(:tracker_id) unless @project.tracker_ids.include?(attributes[:tracker_id].to_i)
    attributes
  end

  def redirect_to_settings
    redirect_to settings_project_path(@project, tab: "reporting")
  end
end
