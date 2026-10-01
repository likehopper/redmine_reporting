# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/capabilities.rb
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
  # What the reporting scope lets the user see. Redmine only grants a permission where its
  # module is enabled, so this follows both the project modules (issue tracking, time
  # tracking) and the user's roles, on any project of the reporting subtree.
  class Capabilities
    PERMISSIONS = {issues: :view_issues, time: :view_time_entries}.freeze

    def initialize(user, projects)
      projects = projects.to_a
      @granted = PERMISSIONS.transform_values { |permission| projects.any? { |project| user.allowed_to?(permission, project) } }
    end

    def issues?
      @granted[:issues]
    end

    def time?
      @granted[:time]
    end

    def any?
      @granted.values.any?
    end

    def allows?(tab)
      tab.needs.all? { |need| @granted[need] }
    end

    def tabs(section)
      section.tabs.select { |tab| allows?(tab) }.map(&:id)
    end
  end
end
