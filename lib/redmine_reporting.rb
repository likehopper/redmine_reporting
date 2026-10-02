# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting.rb
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

require "delegate"
require_relative "redmine_reporting/query_description"
require_relative "redmine_reporting/dashboard_presenter"
require_relative "redmine_reporting/yearly_date"
require_relative "redmine_reporting/period_grid"
require_relative "redmine_reporting/issue_history"
require_relative "redmine_reporting/issue_timeline"
require_relative "redmine_reporting/spent_time"
require_relative "redmine_reporting/credit_ledger"
require_relative "redmine_reporting/credit_account"
require_relative "redmine_reporting/report_data"
require_relative "redmine_reporting/reports/base"
require_relative "redmine_reporting/reports/summary"
require_relative "redmine_reporting/reports/flow"
require_relative "redmine_reporting/reports/activity"
require_relative "redmine_reporting/reports/consumption"
require_relative "redmine_reporting/reports/backlog"
require_relative "redmine_reporting/reports/build"
require_relative "redmine_reporting/reports/workload"
require_relative "redmine_reporting/reports/performance"
require_relative "redmine_reporting/report_builder"
require_relative "redmine_reporting/drilldown"
require_relative "redmine_reporting/issue_query_extensions"
require_relative "redmine_reporting/time_entry_query_extensions"
require_relative "redmine_reporting/sections"
require_relative "redmine_reporting/sla_source"
require_relative "redmine_reporting/capabilities"
require_relative "redmine_reporting/project_settings"
require_relative "redmine_reporting/project_patch"
require_relative "redmine_reporting/projects_helper_patch"
require_relative "redmine_reporting/hooks"

module RedmineReporting
  VERSION = "1.0.0"
end
