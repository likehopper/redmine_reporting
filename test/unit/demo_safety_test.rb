# frozen_string_literal: true
require_relative "../test_helper"
require_relative "../../db/demo_data"

class DemoSafetyTest < ActiveSupport::TestCase
  def test_demo_refuses_a_business_database_even_with_the_explicit_flag
    previous = ENV["REPORTING_DEMO_DATABASE"]
    ENV["REPORTING_DEMO_DATABASE"] = "disposable"
    assert_no_difference ["Project.count", "User.count", "Role.count", "IssueStatus.count"] do
      assert_raises(RuntimeError) { RedmineReporting::DemoData.load }
    end
  ensure
    ENV["REPORTING_DEMO_DATABASE"] = previous
  end

  def test_demo_refuses_production_even_with_the_explicit_flag
    Rails.stubs(:env).returns(ActiveSupport::StringInquirer.new("production"))
    assert_raises(RuntimeError) { RedmineReporting::DemoData.load }
  end

  def test_demo_refuses_a_user_collision_and_never_creates_active_accounts
    demo = RedmineReporting::DemoData.new
    users = demo.send(:ensure_collaborators)
    assert users.all?(&:locked?)
    users.first.update!(admin: true)
    assert_raises(RuntimeError) { demo.send(:ensure_collaborators) }
    assert users.first.reload.admin?
  end
end
