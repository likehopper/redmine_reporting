# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_credit_envelope.rb
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

# A share of a contract's credit: its days are granted on the contract's first day, and it
# is charged with the contract's time on its activities and issue privacy. An envelope for
# "other activities" takes what no other envelope of the contract matches.
class ReportingCreditEnvelope < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  PRIVACIES = %w[all public private].freeze

  # Renewal form only: the previous contract's envelope, and whether to take over its balance.
  attr_accessor :carry_source_id, :carry

  belongs_to :contract, class_name: "ReportingCreditContract", inverse_of: :envelopes
  has_many :movements, -> { order(:date, :id) }, class_name: "ReportingCreditMovement", foreign_key: :envelope_id,
                                                 inverse_of: :envelope, dependent: :destroy
  # Carry-overs into later contracts point back here; they stay if this envelope goes.
  has_many :carried_movements, class_name: "ReportingCreditMovement", foreign_key: :source_envelope_id,
                               dependent: :nullify

  if ActiveRecord::VERSION::MAJOR < 7
    serialize :activity_ids, JSON
  else
    serialize :activity_ids, coder: JSON, type: Array
  end

  accepts_nested_attributes_for :movements, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["days"].blank? }

  validates :name, presence: true
  validates :days, numericality: {greater_than_or_equal_to: 0}
  validates :issue_privacy, inclusion: {in: PRIVACIES}
  validate :activities_must_be_chosen

  after_initialize :apply_defaults, if: :new_record?

  def activity_ids=(ids)
    super(Array(ids).reject(&:blank?).map(&:to_i).uniq.sort)
  end

  def activities
    TimeEntryActivity.where(id: activity_ids).sorted.to_a
  end

  def live_movements
    movements.reject(&:marked_for_destruction?)
  end

  # Two envelopes overlap when some time could match both: the same kind (listed activities,
  # or the remainder), a shared activity for listed ones, and compatible privacy.
  def overlaps?(other)
    return false unless other_activities == other.other_activities
    return false if !other_activities && (activity_ids & other.activity_ids).empty?

    issue_privacy == "all" || other.issue_privacy == "all" || issue_privacy == other.issue_privacy
  end

  def granted_days_between(first_day, last_day)
    contract.starts_on.between?(first_day, last_day) ? days.to_f : 0.0
  end

  # Refills and adjustments dated within the range; adjustments are negative.
  def refilled_days_between(first_day, last_day)
    live_movements.sum { |movement| movement.date&.between?(first_day, last_day) ? movement.days.to_f : 0.0 }
  end

  private

  def apply_defaults
    self.activity_ids ||= []
  end

  def activities_must_be_chosen
    errors.add(:activity_ids, :blank) if !other_activities && activity_ids.empty?
  end
end
