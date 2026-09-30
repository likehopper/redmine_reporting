# frozen_string_literal: true
# Executed by container.sh only on its fresh, disposable database.
require Rails.root.join("plugins/redmine_reporting/db/demo_data")
RedmineReporting::DemoData.load
counts = [Project.count, Issue.count, TimeEntry.count]
RedmineReporting::DemoData.load
abort "Demo duplicates" unless counts == [Project.count, Issue.count, TimeEntry.count]
abort "Active demo accounts" if User.where("login LIKE ?", "reporting-%").where.not(status: User::STATUS_LOCKED).exists?
puts "DEMO PASS projects/issues/time_entries=#{counts.inspect}"
