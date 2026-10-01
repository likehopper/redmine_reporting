# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_credit_policy.rb
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

class ReportingCreditPolicy < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :project
  belongs_to :tracker
  has_many :reporting_credit_refills, dependent: :destroy

  # Blank refill rows of the form are ignored; existing ones can be removed.
  accepts_nested_attributes_for :reporting_credit_refills, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["credit_days"].blank? }

  validates :name, presence: true
  validates :initial_credit_days, numericality: { greater_than_or_equal_to: 0 }
  validates :anniversary_month, inclusion: { in: 1..12 }
  validates :anniversary_day, inclusion: { in: 1..31 }
  validates :tracker_id, uniqueness: { scope: :project_id }
  validate :active_until_must_follow_active_from

  scope :active, -> { where(enabled: true) }
  scope :sorted, -> { joins(:tracker).order("#{Tracker.table_name}.position") }

  def sorted_refills
    reporting_credit_refills.sort_by { |refill| [refill.month, refill.day] }
  end

  # Initial credit granted on the anniversaries of the range, while the policy is active.
  def granted_days_between(first_day, last_day)
    RedmineReporting::YearlyDate.between(anniversary_month, anniversary_day, first_day, last_day).
      count { |date| RedmineReporting::YearlyDate.within?(date, active_from, active_until) } * initial_credit_days.to_f
  end

  def refilled_days_between(first_day, last_day)
    reporting_credit_refills.sum { |refill| refill.credit_days_between(first_day, last_day) }
  end

  def copy_to(project)
    copy = project.reporting_credit_policies.build(attributes.except("id", "project_id", "created_at", "updated_at"))
    reporting_credit_refills.each do |refill|
      copy.reporting_credit_refills.build(refill.attributes.except("id", "reporting_credit_policy_id", "created_at", "updated_at"))
    end
    copy.save!
    copy
  end

  private

  def active_until_must_follow_active_from
    return if active_from.blank? || active_until.blank? || active_until >= active_from

    errors.add(:active_until, :greater_than_or_equal_to, count: active_from)
  end
end