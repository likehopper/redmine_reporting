# frozen_string_literal: true
# File: redmine_reporting/test/unit/sla_rules_test.rb
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

# SLA rules that need no SLA plugin: buckets of time used and end of a delay.
class ReportingSlaRulesTest < ActiveSupport::TestCase
  def test_buckets_compare_time_used_with_the_term_and_respect_includes_the_term
    figure = ->(spent) { RedmineReporting::SlaFigures::Figure.new(spent, 100, "priority:1") }
    {0 => "lt50", 49 => "lt50", 50 => "50-80", 79 => "50-80", 80 => "80-100", 100 => "80-100", 101 => "gt100"}.each do |spent, bucket|
      assert_equal bucket, figure.call(spent).bucket, spent
    end
    assert figure.call(100).respected?
    refute figure.call(101).respected?
    assert_equal 0, figure.call(80).excess
    assert_equal 21, figure.call(121).excess
    assert_equal RedmineReporting::SlaFigures::BUCKETS.keys, RedmineReporting::SlaFigures::RESPECTED + ["gt100"]
  end

  def test_a_delay_ends_when_the_issue_last_leaves_its_statuses
    user = User.find(1)
    first, back, last = Time.utc(2026, 3, 2, 12), Time.utc(2026, 3, 5, 12), Time.utc(2026, 3, 9, 12)
    left = ->(status_id, events, statuses = [1]) { history(status_id, events, user).left_on(statuses) }

    assert_equal user.time_to_date(first), left.call(2, [[first, "1", "2"]])
    assert_nil left.call(1, [[first, "1", "2"], [back, "2", "1"]]), "back in a status of the delay: it runs again"
    assert_equal user.time_to_date(last), left.call(3, [[first, "1", "2"], [back, "2", "1"], [last, "1", "3"]])
    assert_equal user.time_to_date(back), left.call(3, [[first, "1", "2"], [back, "2", "3"]], [1, 2]),
      "moves between statuses of the same delay do not end it"
    assert_nil left.call(3, [[first, "2", "3"]]), "never in a status of the delay"
    assert_nil left.call(2, []), "no status history"
  end

  private

  def history(status_id, events, user)
    issue = Issue.new
    issue.status_id = status_id
    RedmineReporting::IssueHistory.new(issue, user, events, [5], IssueStatus.ids)
  end
end
