# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/sla_figures.rb
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
  # Time used and committed term of each issue and SLA type, read from the redmine_sla
  # caches: nothing is computed here, so figures are as fresh as that plugin's cache.
  # The term is the one of the issue's SLA level for its priority, or for the value of the
  # level's custom field. Ruby and SQL share the same integer comparisons.
  class SlaFigures
    # Time used as a share of the term; a delay is respected up to 100 % included.
    BUCKETS = {
      "lt50" => "s.spent * 100 < t.term * 50",
      "50-80" => "s.spent * 100 >= t.term * 50 AND s.spent * 100 < t.term * 80",
      "80-100" => "s.spent * 100 >= t.term * 80 AND s.spent <= t.term",
      "gt100" => "s.spent > t.term"
    }.freeze
    RESPECTED = %w[lt50 50-80 80-100].freeze
    ON_TIME = %w[lt50 50-80].freeze

    # spent and term in business minutes; pivot is "priority:<id>" or "cf:<field id>:<value>".
    Figure = Struct.new(:spent, :term, :pivot) do
      def bucket
        if spent * 100 < term * 50 then "lt50"
        elsif spent * 100 < term * 80 then "50-80"
        elsif spent <= term then "80-100"
        else "gt100"
        end
      end

      def respected?
        spent <= term
      end

      def excess
        [spent - term, 0].max
      end
    end

    def self.installed?
      Redmine::Plugin.installed?(:redmine_sla) && defined?(::SlaCacheSpent) && defined?(::SlaLevelTerm) ? true : false
    end

    # Issue IDs whose time used for an SLA type falls in the given (known) buckets.
    def self.sql_issue_ids(type_id, buckets)
      conditions = buckets.map { |bucket| BUCKETS.fetch(bucket) }
      type_id = type_id.to_i
      <<~SQL.squish
        SELECT c.issue_id FROM sla_caches c
        INNER JOIN sla_levels l ON l.id = c.sla_level_id
        INNER JOIN issues si ON si.id = c.issue_id
        INNER JOIN sla_cache_spents s ON s.sla_cache_id = c.id AND s.sla_type_id = #{type_id}
        LEFT JOIN custom_values cv ON cv.custom_field_id = l.custom_field_id
          AND cv.customized_type = 'Issue' AND cv.customized_id = c.issue_id
        INNER JOIN sla_level_terms t ON t.sla_level_id = c.sla_level_id AND t.sla_type_id = #{type_id} AND t.term > 0
          AND t.sla_priority_id = CASE WHEN l.custom_field_id IS NULL THEN si.priority_id
            ELSE CAST(NULLIF(cv.value, '') AS #{integer_type}) END
        WHERE (#{conditions.map { |condition| "(#{condition})" }.join(' OR ')})
      SQL
    end

    def self.integer_type
      adapter = ActiveRecord::Base.connection.adapter_name.downcase
      if adapter.include?("mysql") then "SIGNED"
      elsif adapter.include?("sqlite") then "INTEGER"
      else "BIGINT"
      end
    end

    # Issues of projects where the user may not view SLA data are left out.
    def initialize(issues, user)
      allowed = Hash.new { |cache, project| cache[project] = user.allowed_to?(:view_sla, project) }
      @issues = issues.select { |issue| allowed[issue.project] }
    end

    def for(issue_id, type_id)
      by_issue.dig(issue_id, type_id)
    end

    # [[pivot, name]] in Redmine's order: highest priority first, custom field values by position.
    def pivots(keys)
      keys.uniq.map { |key| [key, pivot_record(key)] }.select { |_, record| record }.
        sort_by { |key, record| key.start_with?("priority:") ? [0, -record.position.to_i] : [1, record.position.to_i] }.
        map { |key, record| [key, record.name] }
    end

    private

    def pivot_record(key)
      kind, *ids = key.split(":")
      kind == "priority" ? IssuePriority.find_by(id: ids.first) : CustomFieldEnumeration.find_by(id: ids.last)
    end

    def by_issue
      @by_issue ||= self.class.installed? && @issues.any? ? load : {}
    end

    def load
      issues = @issues.index_by(&:id)
      caches = ::SlaCache.where(issue_id: issues.keys).pluck(:id, :issue_id, :sla_level_id)
      levels = ::SlaLevel.where(id: caches.map(&:last).uniq).pluck(:id, :custom_field_id).to_h
      terms = ::SlaLevelTerm.where(sla_level_id: levels.keys).where("term > 0").
        pluck(:sla_level_id, :sla_type_id, :sla_priority_id, :term).to_h { |level, type, pivot, term| [[level, type, pivot], term] }
      values = CustomValue.where(customized_type: "Issue", customized_id: issues.keys, custom_field_id: levels.values.compact.uniq).
        pluck(:customized_id, :custom_field_id, :value).to_h { |issue_id, field_id, value| [[issue_id, field_id], value] }
      spents = ::SlaCacheSpent.where(sla_cache_id: caches.map(&:first)).pluck(:sla_cache_id, :sla_type_id, :spent).group_by(&:first)

      caches.each_with_object({}) do |(cache_id, issue_id, level_id), result|
        field_id = levels[level_id]
        pivot = field_id ? values[[issue_id, field_id]].to_s[/\A\d+\z/]&.to_i : issues[issue_id].priority_id
        next unless pivot

        Array(spents[cache_id]).each do |_, type_id, spent|
          term = terms[[level_id, type_id, pivot]]
          next unless term

          key = field_id ? "cf:#{field_id}:#{pivot}" : "priority:#{pivot}"
          (result[issue_id] ||= {})[type_id] = Figure.new(spent.to_i, term.to_i, key)
        end
      end
    end
  end
end
