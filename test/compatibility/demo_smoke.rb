# frozen_string_literal: true
# File: redmine_reporting/test/compatibility/demo_smoke.rb
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
# Executed by container.sh only on its fresh, disposable database.
require Rails.root.join("plugins/redmine_reporting/db/demo_data")
RedmineReporting::DemoData.load
counts = [Project.count, Issue.count, TimeEntry.count]
if RedmineReporting::DemoData.sla_available?
  # Checked after the first load too: a reload must not hide what the first one missed.
  abort "Demo SLA not configured on every project" unless SlaProjectTracker.distinct.count(:project_id) == Project.count
end
RedmineReporting::DemoData.load
abort "Demo duplicates" unless counts == [Project.count, Issue.count, TimeEntry.count]
abort "Active demo accounts" if User.where("login LIKE ?", "reporting-%").where.not(status: User::STATUS_LOCKED).exists?
puts "DEMO PASS projects/issues/time_entries=#{counts.inspect}"
# With the SLA plugin (PostgreSQL, MySQL), its own computation must give the report delays.
if RedmineReporting::DemoData.sla_available?
  project = Project.find_by!(identifier: RedmineReporting::DemoData::PROJECT_IDENTIFIER)
  query = ReportingQuery.new(name: "Demo", project: project, user: User.where(admin: true).first!)
  query.section = "sla"
  types = RedmineReporting::ReportBuilder.new(query: query, first_day: Date.current << 12, last_day: Date.current).build.fetch(:sla).fetch(:types)
  summary = types.map { |type| [type[:name], type[:ended], type[:respected], type[:running]] }
  abort "No SLA delay in the demo: #{summary.inspect}" unless types.length == 2 && types.all? { |type| type[:ended].positive? }
  puts "DEMO SLA PASS type/ended/respected/running=#{summary.inspect}"
end
