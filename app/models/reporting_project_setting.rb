# frozen_string_literal: true
# File: redmine_reporting/app/models/reporting_project_setting.rb
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

# Per-project reporting configuration. A project without its own row uses its nearest
# configured ancestor, then the defaults below.
class ReportingProjectSetting < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  DEFAULT_SECTION_IDS = %w[run].freeze
  DEFAULT_HOURS_PER_DAY = 8.0

  belongs_to :project

  # Rails 6.1 takes the coder positionally; Rails 7.2+ requires a keyword.
  %i[section_ids run_tracker_ids build_tracker_ids].each do |attribute|
    if ActiveRecord::VERSION::MAJOR < 7
      serialize attribute, JSON
    else
      serialize attribute, coder: JSON, type: Array
    end
  end

  validates :project, presence: true
  validates :project_id, uniqueness: true
  validates :hours_per_day, numericality: {greater_than: 0, less_than_or_equal_to: 24}
  validate :sections_are_selectable
  validate :trackers_have_one_role

  after_initialize :apply_defaults, if: :new_record?

  def self.update_for(project, attributes)
    setting = find_or_initialize_by(project_id: project.id)
    if setting.new_record?
      setting.assign_attributes(self.for(project).attributes.slice("section_ids", "hours_per_day", "run_tracker_ids", "build_tracker_ids"))
    end
    setting.update(attributes)
    setting
  end

  def self.for(project)
    where(project_id: project.self_and_ancestors.select(:id)).joins(:project).
      order("#{Project.table_name}.lft DESC").first || new(project: project)
  end

  def inherited_by?(project)
    persisted? && project_id != project.id
  end

  def section_enabled?(section_id)
    section_ids.include?(section_id.to_s)
  end

  # Run charts only count Run trackers once some are classified; until then every tracker counts.
  def run_scope_tracker_ids
    run_tracker_ids.presence
  end

  def tracker_role(tracker)
    return "run" if run_tracker_ids.include?(tracker.id)
    return "build" if build_tracker_ids.include?(tracker.id)

    ""
  end

  # {tracker_id => "run" | "build" | ""} from the settings form.
  def tracker_roles=(roles)
    roles = roles.to_h.transform_keys(&:to_i)
    self.run_tracker_ids = roles.select { |_, role| role == "run" }.keys.sort
    self.build_tracker_ids = roles.select { |_, role| role == "build" }.keys.sort
  end

  def section_ids=(ids)
    super(Array(ids).map(&:to_s).reject(&:blank?).uniq)
  end

  def copy_to(project)
    self.class.create!(attributes.except("id", "project_id", "created_at", "updated_at", "created_on", "updated_on").
      merge("project_id" => project.id))
  end

  private

  def apply_defaults
    self.section_ids = DEFAULT_SECTION_IDS if section_ids.blank?
    self.run_tracker_ids ||= []
    self.build_tracker_ids ||= []
  end

  def sections_are_selectable
    unknown = section_ids - RedmineReporting::Sections.selectable_ids
    errors.add(:section_ids, :inclusion) if unknown.any?
  end

  def trackers_have_one_role
    errors.add(:build_tracker_ids, :invalid) if (run_tracker_ids & build_tracker_ids).any?
  end
end
