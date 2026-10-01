# frozen_string_literal: true
# File: redmine_reporting/config/routes.rb
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

get "projects/:project_id/reporting", to: "reporting#index", as: "project_reporting"
get "projects/:project_id/reporting/details", to: "reporting#details", as: "project_reporting_details"

patch "projects/:project_id/reporting/settings", to: "reporting_settings#update", as: "project_reporting_settings"
scope "projects/:project_id/reporting", as: "project_reporting" do
  resources :credit_policies, controller: "reporting_credit_policies", only: [:new, :create, :edit, :update, :destroy]
end
