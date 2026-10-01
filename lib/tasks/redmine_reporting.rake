# frozen_string_literal: true
# File: redmine_reporting/lib/tasks/redmine_reporting.rake
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