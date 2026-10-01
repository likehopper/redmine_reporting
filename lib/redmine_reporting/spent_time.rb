# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/spent_time.rb
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
  class SpentTime
    def initialize(time_entry_scope, issue_ids)
      @days = Hash.new { |hash, issue_id| hash[issue_id] = [] }
      time_entry_scope.where(issue_id: issue_ids).group(:issue_id, :spent_on).sum(:hours).
        each { |(issue_id, spent_on), hours| @days[issue_id] << [spent_on, hours.to_f] }
      @days.each_value do |entries|
        total = 0.0
        entries.sort_by!(&:first)
        entries.map! { |day, hours| [day, total += hours] }
      end
    end

    def total(issue)
      @days.fetch(issue.id, []).last&.last || 0.0
    end

    def until(issue, date)
      entries = @days.fetch(issue.id, [])
      index = entries.bsearch_index { |day, _| day > date } || entries.length
      index.zero? ? 0.0 : entries[index - 1].last
    end
  end
end
