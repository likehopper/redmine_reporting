# frozen_string_literal: true
# File: redmine_reporting/mirror/adapters.rb
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

module RedmineReporting
  # Redmine Mirror adapters copying a project's reporting configuration from another Redmine.
  # init.rb loads this file only when Mirror is installed: it stays outside app/ and lib/,
  # which Redmine eager-loads even on instances without Mirror.
  module MirrorAdapters
    # Native import: each object is written through the models, in one transaction with
    # its Mirror correspondence. The source only needs the read-only REST API.
    class Base < RedmineMirror::Adapters::Base
      def api_version; 1; end

      def mapping_tables
        [RedmineMirror::MappingTable.new("tracker")]
      end

      def catalog_references(client, project_id)
        project = client.get("projects/#{Integer(project_id)}.json", "include" => "trackers").fetch("project")
        {"tracker" => project.fetch("trackers", [])}
      end

      # Same rules as Mirror's own adapters: match through stored IDs only, refuse to
      # overwrite a local change or an unmapped local object, never propagate deletions.
      def synchronize(record, project_id:, mappings:, lookup:, store:, source:, apply:)
        project = Project.find(project_id)
        imported = imported_attributes(record, mappings)
        row = store.find(key, record.fetch("id"))
        target = row ? find_local(project, row.fetch("destination_id")) : unmapped_local(project, imported)
        raise RedmineMirror::Error, "Destination #{key} moved or missing" if row && !target
        # Worded so Mirror records a conflict the project can resolve by keeping the local object.
        raise RedmineMirror::Error, "Existing local #{key} object for source ID #{record.fetch('id')}" if !row && target
        if row && digest(local_attributes(target)) != row.fetch("destination_fingerprint")
          raise RedmineMirror::Error, "Local modification detected for #{key} source ID #{record.fetch('id')}"
        end
        action = row ? (digest(imported) == row.fetch("source_fingerprint") ? "unchanged" : "update") : "create"
        if action != "unchanged"
          target ||= build(project)
          assign(target, imported)
          raise RedmineMirror::Error, "Destination rejected #{key}: #{target.errors.full_messages.join(', ')}" unless target.valid?
          if apply
            target.class.transaction do
              target.save!
              store.save(key, record.fetch("id"), "destination_id" => target.id,
                "source_fingerprint" => digest(imported), "destination_fingerprint" => digest(local_attributes(target.reload)))
            end
          end
        end
        {module: key, source_id: record.fetch("id"), destination_id: target&.persisted? ? target.id : nil, action: action}
      end

      def digest(value)
        Digest::SHA256.hexdigest(JSON.generate(value))
      end

      def tracker_id(mappings, tracker)
        map(mappings, "tracker", tracker.fetch("id"))
      end

      def remote_project_path(setting)
        "projects/#{Integer(setting.source_project_id)}"
      end
    end

    # Hours per day, enabled sections and Run/Build tracker roles. Only a configuration
    # owned by the source project is copied: inherited or default values stay with their owner.
    class Settings < Base
      def key; "reporting_settings"; end

      def records(client, project_id)
        setting = client.get("projects/#{Integer(project_id)}/reporting/settings.json").fetch("reporting_setting")
        setting["id"].nil? || setting.key?("inherited_from") ? [] : [setting]
      end

      def imported_attributes(record, mappings)
        {"hours_per_day" => record.fetch("hours_per_day").to_f, "section_ids" => record.fetch("section_ids"),
         "run_tracker_ids" => record.fetch("run_trackers").map { |tracker| tracker_id(mappings, tracker) }.sort,
         "build_tracker_ids" => record.fetch("build_trackers").map { |tracker| tracker_id(mappings, tracker) }.sort}
      end

      def local_attributes(setting)
        {"hours_per_day" => setting.hours_per_day.to_f, "section_ids" => setting.section_ids,
         "run_tracker_ids" => setting.run_tracker_ids.sort, "build_tracker_ids" => setting.build_tracker_ids.sort}
      end

      def find_local(project, id)
        ReportingProjectSetting.find_by(project_id: project.id, id: id)
      end

      def unmapped_local(project, _imported)
        ReportingProjectSetting.find_by(project_id: project.id)
      end

      def build(project)
        ReportingProjectSetting.new(project: project)
      end

      def assign(setting, imported)
        setting.assign_attributes(imported)
      end

      def local_path(_id, project)
        "/projects/#{project.identifier}/settings/reporting"
      end

      def remote_path(_id, setting)
        "#{remote_project_path(setting)}/settings/reporting"
      end
    end

    # Credit contracts with their envelopes and movements, replaced together. Trackers and
    # activities go through Mirror's mappings; an ignored one is left out of the contract,
    # and a contract left without any tracker is ignored. Carry-over links stay on the source.
    class CreditContracts < Base
      def key; "reporting_credit_contracts"; end

      def mapping_tables
        super + [RedmineMirror::MappingTable.new("activity")]
      end

      def catalog_references(client, project_id)
        super.merge("activity" => client.get("enumerations/time_entry_activities.json").fetch("time_entry_activities"))
      end

      def records(client, project_id)
        path = "projects/#{Integer(project_id)}/reporting/credit_contracts.json"
        Enumerator.new do |records|
          offset = 0
          loop do
            page = client.get(path, "offset" => offset, "limit" => 100)
            contracts = page.fetch("reporting_credit_contracts")
            contracts.each { |contract| records << contract }
            offset += contracts.size
            break if offset >= Integer(page.fetch("total_count"))
            raise RedmineMirror::Error, "Pagination made no progress" if contracts.empty?
          end
        end
      end

      def used_references(record)
        {"tracker" => record.fetch("trackers").map { |tracker| tracker.fetch("id") },
         "activity" => record.fetch("envelopes").flat_map { |envelope| envelope.fetch("activities").map { |activity| activity.fetch("id") } }.uniq}
      end

      def ignored_reference(record, mappings)
        trackers = record.fetch("trackers")
        "tracker" if trackers.any? && trackers.all? { |tracker| ignored_mapping?(mappings, "tracker", tracker.fetch("id")) }
      end

      def imported_attributes(record, mappings)
        {"name" => record.fetch("name"), "description" => record["description"],
         "starts_on" => record.fetch("starts_on"), "ends_on" => record.fetch("ends_on"),
         "include_subprojects" => record.fetch("include_subprojects"),
         "tracker_ids" => mapped_ids(mappings, "tracker", record.fetch("trackers")),
         "envelopes" => record.fetch("envelopes").sort_by { |envelope| [envelope.fetch("position"), envelope.fetch("id")] }.map do |envelope|
           {"name" => envelope.fetch("name"), "days" => envelope.fetch("days").to_f, "other_activities" => envelope.fetch("other_activities"),
            "issue_privacy" => envelope.fetch("issue_privacy"), "activity_ids" => mapped_ids(mappings, "activity", envelope.fetch("activities")),
            "movements" => normalize_movements(envelope.fetch("movements").map do |movement|
              {"date" => movement.fetch("date"), "days" => movement.fetch("days").to_f, "comment" => movement["comment"]}
            end)}
         end}
      end

      def local_attributes(contract)
        {"name" => contract.name, "description" => contract.description, "starts_on" => contract.starts_on&.iso8601,
         "ends_on" => contract.ends_on&.iso8601, "include_subprojects" => contract.include_subprojects,
         "tracker_ids" => contract.tracker_ids.sort,
         "envelopes" => contract.envelopes.reject(&:marked_for_destruction?).map do |envelope|
           {"name" => envelope.name, "days" => envelope.days.to_f, "other_activities" => envelope.other_activities,
            "issue_privacy" => envelope.issue_privacy, "activity_ids" => envelope.activity_ids.sort,
            "movements" => normalize_movements(envelope.movements.reject(&:marked_for_destruction?).map do |movement|
              {"date" => movement.date&.iso8601, "days" => movement.days.to_f, "comment" => movement.comment}
            end)}
         end}
      end

      def normalize_movements(movements)
        movements.sort_by { |movement| movement.values.map(&:to_s) }
      end

      def mapped_ids(mappings, kind, references)
        references.reject { |reference| ignored_mapping?(mappings, kind, reference.fetch("id")) }.
          map { |reference| map(mappings, kind, reference.fetch("id")) }.uniq.sort
      end

      def find_local(project, id)
        project.reporting_credit_contracts.find_by(id: id)
      end

      # A local contract of the same name and start was made by hand: keeping it is the project's call.
      def unmapped_local(project, imported)
        project.reporting_credit_contracts.find_by(name: imported.fetch("name"), starts_on: imported.fetch("starts_on"))
      end

      def build(project)
        project.reporting_credit_contracts.build
      end

      def assign(contract, imported)
        contract.assign_attributes(imported.except("envelopes"))
        contract.envelopes.each(&:mark_for_destruction)
        imported.fetch("envelopes").each_with_index do |envelope, index|
          built = contract.envelopes.build(envelope.except("movements").merge("position" => index))
          envelope.fetch("movements").each { |movement| built.movements.build(movement) }
        end
      end

      def local_path(id, project)
        "/projects/#{project.identifier}/reporting/credit_contracts/#{Integer(id)}/edit"
      end

      def remote_path(id, setting)
        "#{remote_project_path(setting)}/reporting/credit_contracts/#{Integer(id)}/edit"
      end
    end

    ALL = [Settings, CreditContracts].freeze

    # init.rb runs again after each code reload: register each module once.
    def self.register
      ALL.map(&:new).each do |adapter|
        RedmineMirror.register_adapter(adapter) unless RedmineMirror::REGISTRY[adapter.key]
      end
    end
  end
end
