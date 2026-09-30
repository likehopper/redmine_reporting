# frozen_string_literal: true

module RedmineReporting
  class Hooks < Redmine::Hook::Listener
    # Project copies (and project templates) keep their reporting configuration and credits.
    def model_project_copy_before_save(context = {})
      source = context[:source_project]
      target = context[:destination_project]
      source.reporting_project_setting&.copy_to(target)
      source.reporting_credit_policies.includes(:reporting_credit_refills).each do |policy|
        next unless target.trackers.include?(policy.tracker)

        policy.copy_to(target)
      end
    end
  end
end
