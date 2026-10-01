# frozen_string_literal: true
# File: redmine_reporting/test/unit/reporting_credit_policy_test.rb
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

class ReportingCreditPolicyTest < ActiveSupport::TestCase
  fixtures :reporting_credit_policies, :reporting_credit_refills

  def test_anniversary_falls_on_the_last_day_of_short_months
    policy = reporting_credit_policies(:leap_day)
    assert_equal 5, policy.granted_days_between(Date.new(2027, 2, 28), Date.new(2027, 2, 28))
    assert_equal 0, policy.granted_days_between(Date.new(2028, 2, 28), Date.new(2028, 2, 28))
    assert_equal 5, policy.granted_days_between(Date.new(2028, 2, 29), Date.new(2028, 2, 29))
    refill = reporting_credit_refills(:subproject_september)
    assert_equal 3, refill.credit_days_between(Date.new(2026, 9, 30), Date.new(2026, 9, 30))
  end

  def test_initial_credit_is_granted_on_anniversaries_within_the_validity
    feature = reporting_credit_policies(:ecookbook_feature)
    bug = reporting_credit_policies(:ecookbook_bug)
    assert_equal 20, feature.granted_days_between(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    assert_equal 0, feature.granted_days_between(Date.new(2026, 2, 1), Date.new(2026, 12, 31))
    # Before active_from, and after active_until.
    assert_equal 0, feature.granted_days_between(Date.new(2025, 1, 1), Date.new(2025, 12, 31))
    assert_equal 0, bug.granted_days_between(Date.new(2027, 1, 1), Date.new(2027, 1, 31))
    # Every anniversary of a longer range counts.
    assert_equal 40, feature.granted_days_between(Date.new(2026, 1, 1), Date.new(2027, 12, 31))
    assert_equal 10, bug.granted_days_between(Date.new(2026, 1, 1), Date.new(2027, 12, 31))
  end

  def test_refills_follow_their_own_dates_and_validity
    feature = reporting_credit_policies(:ecookbook_feature)
    support = reporting_credit_policies(:ecookbook_support)
    assert_equal 5, feature.refilled_days_between(Date.new(2026, 7, 1), Date.new(2026, 7, 31))
    assert_equal 0, feature.refilled_days_between(Date.new(2026, 6, 1), Date.new(2026, 6, 30))
    assert_equal 10, feature.refilled_days_between(Date.new(2026, 1, 1), Date.new(2027, 12, 31))
    assert_equal 5, support.refilled_days_between(Date.new(2026, 1, 1), Date.new(2027, 12, 31))
    assert_equal 0, reporting_credit_policies(:ecookbook_bug).refilled_days_between(Date.new(2026, 1, 1), Date.new(2026, 12, 31))
  end

  def test_active_scope_and_validity_validation
    refute_includes ReportingCreditPolicy.active, reporting_credit_policies(:disabled)
    policy = reporting_credit_policies(:ecookbook_bug)
    policy.active_until = Date.new(2025, 12, 31)
    refute policy.valid?
    assert policy.errors.key?(:active_until)
    refill = reporting_credit_refills(:support_july)
    refill.ends_on = Date.new(2025, 1, 1)
    refute refill.valid?
    assert refill.errors.key?(:ends_on)
  end

  def test_sorted_refills_follow_the_calendar
    policy = reporting_credit_policies(:ecookbook_feature)
    policy.reporting_credit_refills.create!(month: 3, day: 15, credit_days: 2)
    assert_equal [[3, 15], [7, 1]], policy.reload.sorted_refills.map { |refill| [refill.month, refill.day] }
  end
end
