# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_credit_movement.rb
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

# A dated change to an envelope's credit: a refill (positive) or an adjustment (negative).
# A carry-over from a previous contract also names the envelope it comes from.
class ReportingCreditMovement < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :envelope, class_name: "ReportingCreditEnvelope", inverse_of: :movements
  belongs_to :source_envelope, class_name: "ReportingCreditEnvelope", optional: true

  validates :date, presence: true
  validates :days, numericality: {other_than: 0}
  validates :comment, length: {maximum: 255}
  validate :date_must_fall_within_the_contract

  private

  def date_must_fall_within_the_contract
    contract = envelope&.contract
    return if date.blank? || contract.nil? || contract.starts_on.blank? || contract.ends_on.blank? || contract.covers?(date)

    errors.add(:date, :reporting_outside_contract)
  end
end
