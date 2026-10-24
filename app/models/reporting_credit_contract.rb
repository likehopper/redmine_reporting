# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_credit_contract.rb
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

# A credit contract: dates, covered trackers, and the envelopes its credit is split into.
# Time logged on an issue of a covered tracker within the dates is charged to the envelope
# matching its activity and the issue's privacy. With include_subprojects, the subprojects'
# time counts too, unless a closer contract covers the same tracker on that date.
class ReportingCreditContract < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :project
  has_many :envelopes, -> { order(:position, :id) }, class_name: "ReportingCreditEnvelope", foreign_key: :contract_id,
                                                     inverse_of: :contract, dependent: :destroy

  # Rails 6.1 takes the coder positionally; Rails 7.2+ requires a keyword.
  if ActiveRecord::VERSION::MAJOR < 7
    serialize :tracker_ids, JSON
  else
    serialize :tracker_ids, coder: JSON, type: Array
  end

  # Blank envelope rows of the form are ignored; existing ones can be removed.
  accepts_nested_attributes_for :envelopes, allow_destroy: true,
    reject_if: ->(attributes) { attributes["id"].blank? && attributes["name"].blank? && attributes["days"].blank? }

  validates :project, :name, :starts_on, :ends_on, presence: true
  validate :ends_on_must_follow_starts_on
  validate :trackers_must_exist
  validate :trackers_must_not_overlap_another_contract
  validate :envelopes_must_not_overlap

  after_initialize { self.tracker_ids ||= [] }

  scope :sorted, -> { order(starts_on: :desc, id: :desc) }

  def tracker_ids=(ids)
    super(Array(ids).reject(&:blank?).map(&:to_i).uniq.sort)
  end

  def trackers
    Tracker.where(id: tracker_ids).sorted.to_a
  end

  def live_envelopes
    envelopes.reject(&:marked_for_destruction?)
  end

  def covers?(date)
    date >= starts_on && date <= ends_on
  end

  def overlaps?(other)
    starts_on <= other.ends_on && other.starts_on <= ends_on
  end

  def status(today)
    if today < starts_on then "upcoming"
    elsif today > ends_on then "finished"
    else "current"
    end
  end

  def days
    live_envelopes.sum { |envelope| envelope.days.to_f }
  end

  # The next contract, the day after this one, with the same trackers and envelopes, over the
  # same number of months when it lasts whole months, or else of days. Movements are not
  # copied: a carry-over is a choice made at renewal.
  def renewal
    next_start = ends_on + 1
    months = (1..600).find { |count| (starts_on >> count) - 1 >= ends_on }
    next_end = months && (starts_on >> months) - 1 == ends_on ? (next_start >> months) - 1 : next_start + (ends_on - starts_on)
    copy = self.class.new(project: project, name: name, description: description, tracker_ids: tracker_ids,
                          include_subprojects: include_subprojects, starts_on: next_start, ends_on: next_end)
    envelopes.each do |envelope|
      copy.envelopes.build(envelope.attributes.slice("name", "days", "activity_ids", "other_activities", "issue_privacy", "position"))
    end
    copy
  end

  # Project copies keep the contract on the trackers the copy still has; nil when none is left.
  def copy_to(target)
    copy = renewal
    copy.assign_attributes(project: target, starts_on: starts_on, ends_on: ends_on, tracker_ids: tracker_ids & target.tracker_ids)
    envelopes.zip(copy.envelopes).each do |envelope, copied|
      envelope.movements.each { |movement| copied.movements.build(movement.attributes.slice("date", "days", "comment")) }
    end
    copy.save ? copy : nil
  end

  private

  def ends_on_must_follow_starts_on
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, :greater_than_or_equal_to, count: starts_on)
  end

  def trackers_must_exist
    if tracker_ids.empty?
      errors.add(:tracker_ids, :blank)
    elsif Tracker.where(id: tracker_ids).count != tracker_ids.size
      errors.add(:tracker_ids, :invalid)
    end
  end

  # One tracker belongs to at most one contract of the project on any date.
  def trackers_must_not_overlap_another_contract
    return if project.nil? || starts_on.blank? || ends_on.blank?

    others = self.class.where(project_id: project_id).where.not(id: id).
      where("starts_on <= ? AND ends_on >= ?", ends_on, starts_on).to_a
    clash = others.find { |other| (other.tracker_ids & tracker_ids).any? }
    errors.add(:base, :reporting_contract_overlap, name: clash.name) if clash
  end

  def envelopes_must_not_overlap
    list = live_envelopes
    errors.add(:base, :reporting_envelope_required) if list.empty?
    list.combination(2).each do |first, second|
      next unless first.overlaps?(second)

      errors.add(:base, :reporting_envelope_overlap, first: first.name, second: second.name)
    end
  end
end
