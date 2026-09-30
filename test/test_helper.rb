# frozen_string_literal: true

require File.expand_path("../../../test/test_helper", __dir__)

# The plugin's own tables have fixtures next to Redmine's; core tables keep Redmine's fixtures.
if ActiveSupport::TestCase.respond_to?(:fixture_paths)
  ActiveSupport::TestCase.fixture_paths += [File.expand_path("fixtures", __dir__)]
else
  # Rails 6.1 only accepts one fixture directory. Merge into a disposable directory
  # so the Redmine checkout and its own fixtures remain unchanged.
  require "tmpdir"
  fixture_directory = Dir.mktmpdir("redmine-reporting-fixtures-")
  [ActiveSupport::TestCase.fixture_path, File.expand_path("fixtures", __dir__)].each do |source|
    FileUtils.cp_r(Dir.glob(File.join(source, "*")), fixture_directory)
  end
  ActiveSupport::TestCase.fixture_path = fixture_directory
  Minitest.after_run { FileUtils.remove_entry(fixture_directory) }
end

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
