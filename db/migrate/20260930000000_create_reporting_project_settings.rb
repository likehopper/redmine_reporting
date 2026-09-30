# frozen_string_literal: true

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
