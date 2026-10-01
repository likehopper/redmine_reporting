# frozen_string_literal: true
# File: redmine_reporting/db/migrate/20260930000000_create_reporting_project_settings.rb
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

class CreateReportingProjectSettings < ActiveRecord::Migration[4.2]
  def change
    create_table :reporting_project_settings do |t|
      t.references :project, null: false, index: {unique: true, name: "idx_reporting_project_settings_project"}
      # JSON arrays: enabled report sections and tracker classification.
      t.text :section_ids
      t.decimal :hours_per_day, precision: 5, scale: 2, null: false, default: 8
      t.text :run_tracker_ids
      t.text :build_tracker_ids
      t.string :status_source, null: false, default: "sla"
      t.text :waiting_status_ids
      t.timestamps null: false
    end
  end
end
