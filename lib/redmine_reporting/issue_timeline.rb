# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/issue_timeline.rb
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
  # An issue seen through its creation and closure dates, in the viewer's time zone as
  # Redmine's own date filters are. Closure follows Redmine: closed_on is the last closing
  # date and is kept when the issue is reopened, while closed? reads the current status.
  class IssueTimeline
    attr_reader :issue, :created_on, :closed_on

    delegate :id, :tracker, :priority, :status, :estimated_hours, :closed?, to: :issue

    def initialize(issue, user, history: nil)
      @issue = issue
      @history = history || IssueHistory.new(issue, user)
      @created_on = issue.created_on && user.time_to_date(issue.created_on)
      @closed_on = issue.closed_on && user.time_to_date(issue.closed_on)
    end

    def created_between?(first_day, last_day)
      created_on.present? && created_on.between?(first_day, last_day)
    end

    def closed_between?(first_day, last_day)
      closed_on.present? && closed_on.between?(first_day, last_day)
    end

    # Historical backlog: created by then and not closed yet at that date.
    def in_backlog_on?(date)
      created_on.present? && created_on <= date && @history.open_on?(date)
    end

    # Open at some point of the range: created before its end, and not closed before its start.
    def alive_between?(first_day, last_day)
      created_on.present? && created_on <= last_day && (!closed? || closed_on.nil? || closed_on >= first_day)
    end

    def age_on(date)
      (date - created_on).to_i
    end

    def resolution_days
      (closed_on - created_on).to_i
    end
  end
end
