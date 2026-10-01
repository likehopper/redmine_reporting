# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/projects_helper_patch.rb
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
  # Adds the "Reporting" tab to the project settings.
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:reporting) && User.current.allowed_to?(:manage_reporting, @project)
        tabs << {name: "reporting", action: :manage_reporting, partial: "reporting_settings/show", label: :label_reporting}
      end
      tabs
    end
  end
end
