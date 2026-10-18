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

    # One credit policy per tracker, with its refills; the refills belong to the policy
    # and are replaced together with it.
    class CreditPolicies < Base
      def key; "reporting_credit_policies"; end

      def records(client, project_id)
        path = "projects/#{Integer(project_id)}/reporting/credit_policies.json"
        Enumerator.new do |records|
          offset = 0
          loop do
            page = client.get(path, "offset" => offset, "limit" => 100)
            policies = page.fetch("reporting_credit_policies")
            policies.each { |policy| records << policy }
            offset += policies.size
            break if offset >= Integer(page.fetch("total_count"))
            raise RedmineMirror::Error, "Pagination made no progress" if policies.empty?
          end
        end
      end

      def imported_attributes(record, mappings)
        {"tracker_id" => tracker_id(mappings, record.fetch("tracker")), "name" => record.fetch("name"),
         "initial_credit_days" => record.fetch("initial_credit_days").to_f,
         "anniversary_month" => record.fetch("anniversary_month"), "anniversary_day" => record.fetch("anniversary_day"),
         "active_from" => record["active_from"], "active_until" => record["active_until"], "enabled" => record.fetch("enabled"),
         "refills" => normalize_refills(record.fetch("refills").map do |refill|
           {"month" => refill.fetch("month"), "day" => refill.fetch("day"), "credit_days" => refill.fetch("credit_days").to_f,
            "starts_on" => refill["starts_on"], "ends_on" => refill["ends_on"]}
         end)}
      end

      def local_attributes(policy)
        {"tracker_id" => policy.tracker_id, "name" => policy.name, "initial_credit_days" => policy.initial_credit_days.to_f,
         "anniversary_month" => policy.anniversary_month, "anniversary_day" => policy.anniversary_day,
         "active_from" => policy.active_from&.iso8601, "active_until" => policy.active_until&.iso8601, "enabled" => policy.enabled,
         "refills" => normalize_refills(policy.reporting_credit_refills.map do |refill|
           {"month" => refill.month, "day" => refill.day, "credit_days" => refill.credit_days.to_f,
            "starts_on" => refill.starts_on&.iso8601, "ends_on" => refill.ends_on&.iso8601}
         end)}
      end

      def normalize_refills(refills)
        refills.sort_by { |refill| refill.values.map(&:to_s) }
      end

      def find_local(project, id)
        project.reporting_credit_policies.find_by(id: id)
      end

      # The destination accepts one policy per tracker.
      def unmapped_local(project, imported)
        project.reporting_credit_policies.find_by(tracker_id: imported.fetch("tracker_id"))
      end

      def build(project)
        project.reporting_credit_policies.build
      end

      def assign(policy, imported)
        policy.assign_attributes(imported.except("refills"))
        policy.reporting_credit_refills.each(&:mark_for_destruction)
        imported.fetch("refills").each { |refill| policy.reporting_credit_refills.build(refill) }
      end

      def local_path(id, project)
        "/projects/#{project.identifier}/reporting/credit_policies/#{Integer(id)}/edit"
      end

      def remote_path(id, setting)
        "#{remote_project_path(setting)}/reporting/credit_policies/#{Integer(id)}/edit"
      end
    end

    ALL = [Settings, CreditPolicies].freeze

    # init.rb runs again after each code reload: register each module once.
    def self.register
      ALL.map(&:new).each do |adapter|
        RedmineMirror.register_adapter(adapter) unless RedmineMirror::REGISTRY[adapter.key]
      end
    end
  end
end
