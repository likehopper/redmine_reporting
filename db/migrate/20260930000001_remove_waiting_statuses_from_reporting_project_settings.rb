# frozen_string_literal: true

# Waiting statuses come from the redmine_sla plugin only: a manual list would duplicate it
# without being enough to compute meaningful delays.
class RemoveWaitingStatusesFromReportingProjectSettings < ActiveRecord::Migration[4.2]
  def change
    remove_column :reporting_project_settings, :status_source, :string, null: false, default: "sla"
    remove_column :reporting_project_settings, :waiting_status_ids, :text
  end
end
