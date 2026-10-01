# frozen_string_literal: true
# File: redmine_reporting/db/migrate/20260930000001_remove_waiting_statuses_from_reporting_project_settings.rb
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

# Waiting statuses come from the redmine_sla plugin only: a manual list would duplicate it
# without being enough to compute meaningful delays.
class RemoveWaitingStatusesFromReportingProjectSettings < ActiveRecord::Migration[4.2]
  def change
    remove_column :reporting_project_settings, :status_source, :string, null: false, default: "sla"
    remove_column :reporting_project_settings, :waiting_status_ids, :text
  end
end
