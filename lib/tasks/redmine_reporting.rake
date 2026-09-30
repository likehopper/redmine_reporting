# frozen_string_literal: true

namespace :redmine do
  namespace :plugins do
    namespace :redmine_reporting do
      desc "Create or refresh the RedmineReporting demonstration project and data"
      task seed_demo: :environment do
        # Outside lib/ so production boots never load it.
        require_relative "../../db/demo_data"
        project = RedmineReporting::DemoData.load
        project_ids = project.self_and_descendants.pluck(:id)
        issue_count = Issue.where(project_id: project_ids).count
        time_entry_count = TimeEntry.where(project_id: project_ids).count
        puts "Reporting demo ready: #{project.identifier} (#{project_ids.length - 1} subprojects, #{issue_count} issues, #{time_entry_count} time entries)"
      end
    end
  end
end