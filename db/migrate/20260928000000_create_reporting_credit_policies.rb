# frozen_string_literal: true
# File: redmine_reporting/db/migrate/20260928000000_create_reporting_credit_policies.rb
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

class CreateReportingCreditPolicies < ActiveRecord::Migration[4.2]
  def change
    create_table :reporting_credit_policies do |t|
      t.references :project, null: false
      t.references :tracker, null: false
      t.string :name, null: false
      t.decimal :initial_credit_days, precision: 10, scale: 2, null: false, default: 0
      t.integer :anniversary_month, null: false
      t.integer :anniversary_day, null: false
      t.date :active_from
      t.date :active_until
      t.boolean :enabled, null: false, default: true
      t.timestamps null: false
    end

    add_index :reporting_credit_policies, [:project_id, :tracker_id], unique: true,
      name: "idx_reporting_credit_policies_project_tracker"

    create_table :reporting_credit_refills do |t|
      t.references :reporting_credit_policy, null: false, index: {
        name: "idx_reporting_credit_refills_policy"
      }
      t.integer :month, null: false
      t.integer :day, null: false
      t.decimal :credit_days, precision: 10, scale: 2, null: false
      t.date :starts_on
      t.date :ends_on
      t.timestamps null: false
    end
  end
end