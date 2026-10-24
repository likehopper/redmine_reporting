# frozen_string_literal: true
# File: redmine_reporting/db/migrate/20261024000000_replace_credit_policies_with_contracts.rb
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

# Yearly credit policies give way to dated contracts. Policies had no production use, so
# they are dropped rather than converted.
class ReplaceCreditPoliciesWithContracts < ActiveRecord::Migration[4.2]
  def up
    drop_table :reporting_credit_refills if table_exists?(:reporting_credit_refills)
    drop_table :reporting_credit_policies if table_exists?(:reporting_credit_policies)

    create_table :reporting_credit_contracts do |t|
      t.references :project, null: false, index: {name: "idx_reporting_credit_contracts_project"}
      t.string :name, null: false
      t.text :description
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      # JSON array of the covered trackers.
      t.text :tracker_ids
      t.boolean :include_subprojects, null: false, default: false
      t.timestamps null: false
    end

    create_table :reporting_credit_envelopes do |t|
      t.references :contract, null: false, index: {name: "idx_reporting_credit_envelopes_contract"}
      t.string :name, null: false
      t.decimal :days, precision: 10, scale: 2, null: false, default: 0
      # JSON array of the covered activities, unless other_activities takes the remainder.
      t.text :activity_ids
      t.boolean :other_activities, null: false, default: false
      t.string :issue_privacy, null: false, default: "all"
      t.integer :position, null: false, default: 0
      t.timestamps null: false
    end

    create_table :reporting_credit_movements do |t|
      t.references :envelope, null: false, index: {name: "idx_reporting_credit_movements_envelope"}
      t.date :date, null: false
      t.decimal :days, precision: 10, scale: 2, null: false
      t.string :comment
      # Envelope of the previous contract whose balance this movement carries over.
      t.references :source_envelope, index: {name: "idx_reporting_credit_movements_source"}
      t.timestamps null: false
    end
  end

  def down
    drop_table :reporting_credit_movements
    drop_table :reporting_credit_envelopes
    drop_table :reporting_credit_contracts

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
      t.references :reporting_credit_policy, null: false, index: {name: "idx_reporting_credit_refills_policy"}
      t.integer :month, null: false
      t.integer :day, null: false
      t.decimal :credit_days, precision: 10, scale: 2, null: false
      t.date :starts_on
      t.date :ends_on
      t.timestamps null: false
    end
  end
end
