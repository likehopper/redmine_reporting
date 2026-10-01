# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/project_patch.rb
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
  # Reporting configuration belongs to its project and disappears with it.
  module ProjectPatch
    def self.included(base)
      base.has_one :reporting_project_setting, dependent: :destroy
      base.has_many :reporting_credit_policies, dependent: :destroy
    end
  end
end
