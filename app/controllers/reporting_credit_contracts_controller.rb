# frozen_string_literal: true
# File: redmine_reporting/app/controllers/reporting_credit_contracts_controller.rb
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

class ReportingCreditContractsController < ApplicationController
  menu_item :settings
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_contract, only: [:show, :edit, :update, :destroy, :renew]
  before_action :load_settings_page
  accept_api_auth :index, :show

  helper :reporting

  # Contracts are edited from the settings tab; the list and detail are REST API resources.
  def index
    respond_to do |format|
      format.html { redirect_to_settings }
      format.api do
        @offset, @limit = api_offset_and_limit
        scope = @project.reporting_credit_contracts
        @contract_count = scope.count
        @contracts = scope.includes(:project, envelopes: :movements).order(:id).offset(@offset).limit(@limit).to_a
      end
    end
  end

  def show
    respond_to do |format|
      format.html { redirect_to edit_project_reporting_credit_contract_path(project_id: @project, id: @contract) }
      format.api
    end
  end

  # A one-year contract from the first day of the current month, with one envelope for all
  # activities: the simplest contract only needs its trackers and days.
  def new
    start = User.current.today.beginning_of_month
    @contract = @project.reporting_credit_contracts.build(starts_on: start, ends_on: (start >> 12) - 1,
                                                          tracker_ids: @settings_page.contract_trackers.map(&:id))
    @contract.envelopes.build(name: l(:"reporting.contracts.all_activities"), other_activities: true)
  end

  def create
    @contract = @project.reporting_credit_contracts.build
    @contract.assign_attributes(contract_params)
    build_carry_overs
    if @contract.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to_settings
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    @contract.assign_attributes(contract_params)
    if @contract.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to_settings
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # The next contract, prefilled; each envelope may take over the previous balance.
  def renew
    @previous = @contract
    @contract = @previous.renewal
    @contract.envelopes.zip(@previous.envelopes) { |envelope, source| envelope.carry_source_id = source.id }
    render :new
  end

  def destroy
    @contract.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to_settings
  end

  private

  def find_contract
    @contract = @project.reporting_credit_contracts.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def load_settings_page
    @settings_page = RedmineReporting::ProjectSettings.new(@project)
  end

  def contract_params
    attributes = params.require(:reporting_credit_contract).permit(
      :name, :description, :starts_on, :ends_on, :include_subprojects, tracker_ids: [],
      envelopes_attributes: [:id, :name, :days, :other_activities, :issue_privacy, :position, :_destroy, :carry_source_id, :carry,
                             {activity_ids: [], movements_attributes: [:id, :date, :days, :comment, :_destroy]}]
    )
    # Only the project's trackers and shared activities, plus those already chosen.
    allowed_trackers = @settings_page.contract_trackers.map(&:id) + Array(@contract&.tracker_ids)
    attributes[:tracker_ids] = Array(attributes[:tracker_ids]).map(&:to_i) & allowed_trackers if attributes.key?(:tracker_ids)
    Array(attributes[:envelopes_attributes]&.values).each do |envelope|
      next unless envelope.key?(:activity_ids)

      envelope[:activity_ids] = Array(envelope[:activity_ids]).map(&:to_i) & TimeEntryActivity.shared.pluck(:id)
    end
    attributes
  end

  # Carry-overs are computed here from the previous envelope's balance, never taken from the form.
  def build_carry_overs
    @contract.envelopes.each do |envelope|
      next unless envelope.carry == "1" && envelope.carry_source_id.present?

      source = ReportingCreditEnvelope.joins(:contract).
        find_by(id: envelope.carry_source_id, ReportingCreditContract.table_name => {project_id: @project.id})
      next unless source

      days = @settings_page.carry_over(source)
      next if days.zero?

      key = days.positive? ? :carry_over_comment : :debt_comment
      envelope.movements.build(date: @contract.starts_on, days: days, source_envelope: source,
                               comment: l(:"reporting.contracts.#{key}", contract: source.contract.name, envelope: source.name))
    end
  end

  def redirect_to_settings
    redirect_to settings_project_path(@project, tab: "reporting", reporting_pane: "contracts")
  end
end
