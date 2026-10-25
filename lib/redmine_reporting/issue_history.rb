# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/issue_history.rb
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
  # Status transitions, including reopenings. Missing history falls back to the current
  # status and last closure date; deleted status definitions use the same fallback.
  class IssueHistory
    def initialize(issue, user, events = [], closed_status_ids = IssueStatus.where(is_closed: true).ids, status_ids = IssueStatus.ids)
      @issue, @user, @events, @closed_ids, @status_ids = issue, user, events, closed_status_ids, status_ids
    end

    def open_on?(date)
      event = @events.reverse.find { |time, _, _| @user.time_to_date(time) <= date }
      status = event ? event[2] : @events.first&.[](1)
      return !@closed_ids.include?(status.to_i) if status.present? && @status_ids.include?(status.to_i)

      !@issue.closed? || (@issue.closed_on && @user.time_to_date(@issue.closed_on) > date)
    end

    # Date the issue last left the given statuses, unless it is in one of them now. An SLA
    # delay ends there: its clock only runs in these statuses. Same rule as sql_left.
    def left_on(status_ids)
      return if status_ids.include?(@issue.status_id)

      event = @events.reverse.find { |_, old, new| status_ids.include?(old.to_i) && !status_ids.include?(new.to_i) }
      event && @user.time_to_date(event[0])
    end

    # Issue IDs with the time they last left the given statuses (ended_on), for filters.
    def self.sql_left(status_ids)
      values = status_ids.map { |id| Issue.connection.quote(id.to_s) }.join(",")
      "SELECT j.journalized_id AS issue_id, MAX(j.created_on) AS ended_on FROM journals j " \
        "INNER JOIN journal_details d ON d.journal_id = j.id WHERE j.journalized_type = 'Issue' " \
        "AND d.property = 'attr' AND d.prop_key = 'status_id' AND d.old_value IN (#{values}) " \
        "AND d.value NOT IN (#{values}) GROUP BY j.journalized_id"
    end

    # Correlated SQL keeps native pagination/exports and never materializes issue IDs.
    # Both Ruby and SQL use the last transition before the viewer's end of day.
    def self.sql_open_on(date, user)
      connection = Issue.connection
      tomorrow = date + 1
      cutoff = user.time_zone ? user.time_zone.local(tomorrow.year, tomorrow.month, tomorrow.day) : Time.local(tomorrow.year, tomorrow.month, tomorrow.day)
      cutoff = connection.quote(cutoff.utc)
      source = "FROM journal_details rhd INNER JOIN journals rhj ON rhj.id = rhd.journal_id " \
        "WHERE rhj.journalized_type = 'Issue' AND rhj.journalized_id = issues.id " \
        "AND rhd.property = 'attr' AND rhd.prop_key = 'status_id'"
      previous = "SELECT rhd.value #{source} AND rhj.created_on < #{cutoff} ORDER BY rhj.created_on DESC, rhj.id DESC, rhd.id DESC LIMIT 1"
      initial = "SELECT rhd.old_value #{source} ORDER BY rhj.created_on ASC, rhj.id ASC, rhd.id ASC LIMIT 1"
      cast = connection.adapter_name.downcase.include?("mysql") ? "CHAR" : "VARCHAR"
      historical = "SELECT rhs.is_closed FROM issue_statuses rhs WHERE CAST(rhs.id AS #{cast}) = COALESCE((#{previous}), (#{initial}))"
      fallback = "CASE WHEN issues.closed_on >= #{cutoff} THEN #{connection.quoted_false} ELSE (SELECT rcs.is_closed FROM issue_statuses rcs WHERE rcs.id = issues.status_id) END"
      "COALESCE((#{historical}), (#{fallback})) = #{connection.quoted_false}"
    end
  end
end
