# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/version_history.rb
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

module RedmineReporting
  # Replay version transitions without treating an explicit unassignment as missing data.
  class VersionHistory
    def initialize(issue, user, events)
      @issue, @user, @events = issue, user, events
    end

    def on(date)
      event = @events.reverse.find { |time, _, _| @user.time_to_date(time) <= date }
      value = if event then event[2]
              elsif @events.any? then @events.first[1]
              else @issue.fixed_version_id
              end
      value.present? ? value.to_i : nil
    end

    def self.cutoff(date, user)
      tomorrow = date + 1
      time = user.time_zone ? user.time_zone.local(tomorrow.year, tomorrow.month, tomorrow.day) : Time.local(tomorrow.year, tomorrow.month, tomorrow.day)
      Issue.connection.quote(time.utc)
    end

    def self.sql_on(date, user)
      connection = Issue.connection
      source = "FROM journal_details rvd INNER JOIN journals rvj ON rvj.id = rvd.journal_id " \
        "WHERE rvj.journalized_type = 'Issue' AND rvj.journalized_id = issues.id " \
        "AND rvd.property = 'attr' AND rvd.prop_key = 'fixed_version_id'"
      before = "#{source} AND rvj.created_on < #{cutoff(date, user)}"
      previous = "SELECT NULLIF(rvd.value, '') #{before} ORDER BY rvj.created_on DESC, rvj.id DESC, rvd.id DESC LIMIT 1"
      initial = "SELECT NULLIF(rvd.old_value, '') #{source} ORDER BY rvj.created_on ASC, rvj.id ASC, rvd.id ASC LIMIT 1"
      cast = connection.adapter_name.downcase.include?("mysql") ? "CHAR" : "VARCHAR"
      "(CASE WHEN EXISTS(SELECT 1 #{before}) THEN (#{previous}) " \
        "WHEN EXISTS(SELECT 1 #{source}) THEN (#{initial}) ELSE CAST(issues.fixed_version_id AS #{cast}) END)"
    end
  end
end
