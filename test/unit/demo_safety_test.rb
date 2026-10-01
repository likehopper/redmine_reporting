# frozen_string_literal: true
# File: redmine_reporting/test/unit/demo_safety_test.rb
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
