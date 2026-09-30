# frozen_string_literal: true

require_relative "../test_helper"

class IssueTimelineTest < ActiveSupport::TestCase
  def setup
    @user = User.find(2)
    @open = IssueStatus.where(is_closed: false).first!
    @closed = IssueStatus.where(is_closed: true).first!
  end

  def test_dates_follow_the_viewer_time_zone
    @user.pref.update!(time_zone: "Paris")
    timeline = timeline(created_on: Time.utc(2026, 1, 31, 23, 30), status: @open)
    # 23:30 UTC is already February 1 in Paris, as Redmine's date filters see it.
    assert_equal Date.new(2026, 2, 1), timeline.created_on
    refute timeline.created_between?(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
  end

  def test_backlog_and_period_rules
    timeline = timeline(created_on: Time.utc(2026, 1, 10, 12), closed_on: Time.utc(2026, 2, 5, 12), status: @closed)
    assert timeline.created_between?(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    assert timeline.closed_between?(Date.new(2026, 2, 1), Date.new(2026, 2, 28))
    assert timeline.in_backlog_on?(Date.new(2026, 1, 31))
    refute timeline.in_backlog_on?(Date.new(2026, 2, 5))
    refute timeline.in_backlog_on?(Date.new(2026, 1, 9))
    assert timeline.alive_between?(Date.new(2026, 2, 1), Date.new(2026, 2, 28))
    refute timeline.alive_between?(Date.new(2026, 3, 1), Date.new(2026, 3, 31))
    assert_equal 26, timeline.resolution_days
    assert_equal 21, timeline.age_on(Date.new(2026, 1, 31))
  end

  # Redmine keeps closed_on when an issue is reopened: it is still a closure event of its
  # period, but the issue counts as open wherever the current status matters.
  def test_reopened_issue_keeps_its_closure_date_but_is_open
    timeline = timeline(created_on: Time.utc(2026, 1, 10, 12), closed_on: Time.utc(2026, 1, 20, 12), status: @open)
    refute timeline.closed?
    assert timeline.closed_between?(Date.new(2026, 1, 1), Date.new(2026, 1, 31))
    assert timeline.alive_between?(Date.new(2026, 3, 1), Date.new(2026, 3, 31))
  end

  private

  def timeline(status:, created_on:, closed_on: nil)
    issue = Issue.new(status: status, tracker_id: 1, priority_id: 4)
    issue.created_on = created_on
    issue.closed_on = closed_on
    RedmineReporting::IssueTimeline.new(issue, @user)
  end
end
