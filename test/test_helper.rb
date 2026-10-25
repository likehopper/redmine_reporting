# frozen_string_literal: true
# File: redmine_reporting/test/test_helper.rb
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

require File.expand_path("../../../test/test_helper", __dir__)

# Redmine 5.0 does not load core fixtures globally as later releases do.
if ActiveSupport::TestCase.fixture_table_names.empty?
  core_fixtures = Dir.glob(Rails.root.join("test/fixtures/*.yml")).map { |path| File.basename(path, ".yml") }
  ActiveSupport::TestCase.fixtures(*core_fixtures)
end

# Shared records use Redmine's fixtures and automatic transaction rollback.
module ReportingTestData
  def self.included(test_case)
    test_case.setup :prepare_reporting_data
    test_case.teardown { User.current = @previous_user }
  end

  def prepare_reporting_data
    @previous_user = User.current
    @administrator = User.create!(login: "reporting-query-admin", firstname: "Reporting", lastname: "Admin",
                                  mail: "reporting-query-admin@example.test", admin: true,
                                  password: "Reporting-test-123!", password_confirmation: "Reporting-test-123!")
    User.current = @administrator
    @tracker = Tracker.first!
    @project = create_project("reporting-query-parent")
    @child = create_project("reporting-query-child", parent: @project)
    @outside = create_project("reporting-query-outside")
    [@project, @child, @outside].each(&:reload)
    @version = Version.create!(project: @child, name: "Reporting version")
    @parent_issue = create_issue(@project)
    @child_issue = create_issue(@child, fixed_version: @version)
    @outside_issue = create_issue(@outside)
    @entry = TimeEntry.create!(project: @child, issue: @child_issue, user: @administrator,
                               activity: TimeEntryActivity.active.first!, hours: 2, spent_on: Date.current)
    @unassigned_entry = TimeEntry.create!(project: @project, user: @administrator,
                                          activity: TimeEntryActivity.active.first!, hours: 1, spent_on: Date.current)
  end

  def authenticated_session(user)
    session = ActionDispatch::Integration::Session.new(Rails.application)
    session.get "/login"
    token = Nokogiri::HTML(session.response.body).at_css('input[name="authenticity_token"]')&.[]("value")
    session.post "/login", params: {username: user.login, password: "Reporting-test-123!", authenticity_token: token}
    session
  end

  def create_viewer
    viewer = User.create!(login: "reporting-query-viewer", firstname: "Reporting", lastname: "Viewer",
                          mail: "reporting-query-viewer@example.test",
                          password: "Reporting-test-123!", password_confirmation: "Reporting-test-123!")
    role = Role.create!(name: "Reporting query viewer", permissions: [:view_issues, :view_time_entries, :view_reporting])
    Member.create!(project: @project, user: viewer, roles: [role])
    viewer
  end

  def build_query(user: @administrator)
    ReportingQuery.new(name: "Reporting", project: @project, user: user)
  end

  def create_project(identifier, **attributes)
    Project.create!({name: identifier, identifier: identifier, is_public: false, trackers: [@tracker],
                     enabled_module_names: %w[issue_tracking time_tracking reporting]}.merge(attributes))
  end

  # Reloaded: creation callbacks bump lock_version, which would make later update_columns silently no-op.
  def create_issue(project, **attributes)
    Issue.create!({project: project, tracker: @tracker, author: @administrator, subject: "Reporting query issue",
                   status: IssueStatus.first!, priority: IssuePriority.active.first!}.merge(attributes)).reload
  end
end

# A real SLA configuration (redmine_sla installed): a response delay elapsing in New and a
# resolution one in New and Assigned, both with a 60-minute term. Cache rows are written
# directly, as the SLA plugin leaves them, whatever its calendars would compute.
module ReportingSlaData
  def prepare_sla_data
    @project.enable_module!(:sla)
    ReportingProjectSetting.create!(project: @project, section_ids: %w[run sla])
    @new, @assigned = IssueStatus.find(1), IssueStatus.find(2)
    @response = SlaType.create!(name: "Reporting response")
    @resolution = SlaType.create!(name: "Reporting resolution")
    SlaStatus.create!(sla_type: @response, status: @new)
    [@new, @assigned].each { |status| SlaStatus.create!(sla_type: @resolution, status: status) }
    sla = Sla.create!(name: "Reporting SLA")
    @level = SlaLevel.create!(name: "Reporting level", sla: sla, sla_calendar: SlaCalendar.create!(name: "Reporting calendar"))
    @priority = IssuePriority.active.first!
    [@response, @resolution].each do |type|
      SlaLevelTerm.create!(sla_level: @level, sla_type: type, sla_priority_id: @priority.id, priority: @priority, term: 60)
    end
    SlaProjectTracker.create!(project: @project, tracker: @tracker, sla: sla)
    @today = @administrator.today
    @respected = sla_issue(3.days.ago, 30)
    @overrun = sla_issue(3.days.ago, 90)
    @earlier = sla_issue(40.days.ago, 10)
    @running = sla_issue(nil, 70)
  end

  # An issue whose response delay ended at the given time (nil: still New), with its time used.
  def sla_issue(ended_at, spent)
    issue = create_issue(@project, status: @new, priority: @priority)
    if ended_at
      journal = Journal.new(journalized: issue, user: @administrator)
      journal.details << JournalDetail.new(property: "attr", prop_key: "status_id", old_value: @new.id.to_s, value: @assigned.id.to_s)
      journal.save!
      journal.update_columns(created_on: ended_at)
      issue.update_columns(status_id: @assigned.id)
    end
    cache = SlaCache.create!(id: issue.id, project: @project, issue: issue, tracker_id: @tracker.id, sla_level: @level,
                             start_date: issue.created_on)
    SlaCacheSpent.create!(sla_cache: cache, project: @project, issue: issue, sla_type: @response, spent: spent)
    issue
  end
end
