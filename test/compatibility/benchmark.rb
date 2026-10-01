# frozen_string_literal: true
# File: redmine_reporting/test/compatibility/benchmark.rb
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
# Optional deterministic volume probe. Run only against the disposable test database.
require_relative "../test_helper"
require "benchmark"

class ReportingVolumeTest < ActiveSupport::TestCase
  include ReportingTestData

  def test_report_volume
    today = Date.new(2026, 9, 30)
    start = Date.new(2025, 10, 1)
    template = @parent_issue.attributes.except("id", "root_id", "lft", "rgt")
    rows = Array.new(5000) do |index|
      template.merge("subject" => "Volume #{index}", "created_on" => (start + index % 300).to_time,
                     "estimated_hours" => 10, "closed_on" => nil, "root_id" => nil, "lft" => 1, "rgt" => 2)
    end
    rows.each_slice(500) { |batch| Issue.insert_all!(batch) }
    scope = Issue.where(project: @project).where("subject LIKE 'Volume %'")
    scope.update_all("root_id = id")
    entries = scope.ids.flat_map do |id|
      (0...12).map do |month|
        {project_id: @project.id, issue_id: id, user_id: @administrator.id, activity_id: @entry.activity_id,
         hours: 0.5, spent_on: start >> month, tyear: (start >> month).year, tmonth: (start >> month).month,
         tweek: (start >> month).cweek, created_on: Time.current, updated_on: Time.current}
      end
    end
    entries.each_slice(500) { |batch| TimeEntry.insert_all!(batch) }
    query = build_query
    query.add_filter("project_id", "=", [@project.id.to_s])
    # Warm method/autoload caches, then report median of three independent requests.
    run_report = -> { RedmineReporting::ReportBuilder.new(query: query, first_day: start, last_day: today).build }
    run_report.call
    measurements = 3.times.map do
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        count += 1 unless payload[:name] == "SCHEMA" || payload[:cached]
      end
      GC.start
      allocated = GC.stat(:total_allocated_objects)
      elapsed = Benchmark.realtime { run_report.call }
      [elapsed.round(3), count, GC.stat(:total_allocated_objects) - allocated]
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    puts "REPORTING_BENCHMARK issues=5000 entries=60000 measurements(seconds,sql,objects)=#{measurements.inspect}"
    assert_equal 5000, scope.count
  end
end
