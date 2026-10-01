# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/hooks.rb
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
  class Hooks < Redmine::Hook::Listener
    # Project copies (and project templates) keep their reporting configuration and credits.
    def model_project_copy_before_save(context = {})
      source = context[:source_project]
      target = context[:destination_project]
      source.reporting_project_setting&.copy_to(target)
      source.reporting_credit_policies.includes(:reporting_credit_refills).each do |policy|
        next unless target.trackers.include?(policy.tracker)

        policy.copy_to(target)
      end
    end
  end
end
