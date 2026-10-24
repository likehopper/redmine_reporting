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
# Load through __FILE__ rather than require_relative: require_relative resolves symlinks, while
# Zeitwerk loads lib/ through the plugin path as found under plugins/. When that directory is a
# symlink (e.g. a Capistrano shared dir), the two paths differ and every file is loaded twice.
%w[
  query_description
  dashboard_presenter
  period_grid
  issue_history
  version_history
  issue_timeline
  spent_time
  credit_ledger
  credit_scope
  credit_contract_account
  report_data
  reports/base
  reports/summary
  reports/flow
  reports/activity
  reports/consumption
  reports/backlog
  reports/build
  reports/workload
  reports/burnup
  reports/performance
  report_builder
  drilldown
  contract_filters
  issue_query_extensions
  time_entry_query_extensions
  sections
  sla_source
  capabilities
  project_settings
  project_patch
  projects_helper_patch
  hooks
].each { |file| require File.expand_path("redmine_reporting/#{file}", File.dirname(__FILE__)) }

module RedmineReporting
  VERSION = "1.3.1"
end
