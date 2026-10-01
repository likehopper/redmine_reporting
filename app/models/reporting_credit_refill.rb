# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_credit_refill.rb
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

class ReportingCreditRefill < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :reporting_credit_policy

  validates :credit_days, numericality: { greater_than: 0 }
  validates :month, inclusion: { in: 1..12 }
  validates :day, inclusion: { in: 1..31 }
  validate :active_until_must_follow_active_from

  # Credit added on the refill dates of the range that fall within its own validity.
  def credit_days_between(first_day, last_day)
    RedmineReporting::YearlyDate.between(month, day, first_day, last_day).
      count { |date| RedmineReporting::YearlyDate.within?(date, starts_on, ends_on) } * credit_days.to_f
  end

  private

  def active_until_must_follow_active_from
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, :greater_than_or_equal_to, count: starts_on)
  end
end