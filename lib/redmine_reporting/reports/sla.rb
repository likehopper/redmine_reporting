# frozen_string_literal: true
# File: redmine_reporting/lib/redmine_reporting/reports/sla.rb
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
  module Reports
    # Compliance with SLA delays, one block per SLA type. A delay counts in the period where
    # it ended (the issue left the statuses in which its clock runs); the SLA plugin gives
    # its time used and term. Running delays are only known now: the SLA plugin keeps no
    # history, so they are shown when the period includes today.
    class Sla < Base
      RISKS = {"late" => %w[gt100], "warning" => %w[80-100], "on_time" => SlaFigures::ON_TIME}.freeze

      def to_h
        today = data.user.today
        {
          periodLabels: grid.labels,
          periodStarts: grid.starts,
          periodRanges: grid.ranges,
          today: today.iso8601,
          bucketKeys: SlaFigures::BUCKETS.keys,
          respectedBuckets: SlaFigures::RESPECTED,
          riskBuckets: RISKS,
          types: SlaSource.active_statuses_by_type(data.projects).map do |type, statuses|
            type_report(type, statuses.map(&:id), today.between?(first_day, last_day))
          end
        }
      end

      private

      def figures
        data.sla_figures
      end

      def type_report(type, status_ids, current)
        ended = timelines.filter_map do |timeline|
          figure = figures.for(timeline.id, type.id)
          date = figure && timeline.left_on(status_ids)
          [date, figure] if date&.between?(first_day, last_day)
        end
        per_period = grid.map { |period| ended.select { |date, _| date.between?(period.first_day, period.last_day) }.map(&:last) }
        all = ended.map(&:last)

        {
          id: type.id,
          name: type.name,
          ended: all.length,
          respected: all.count(&:respected?),
          rate: rate(all),
          periodEnded: per_period.map(&:length),
          periodRespected: per_period.map { |items| items.count(&:respected?) },
          periodRate: per_period.map { |items| rate(items) },
          periodOverruns: per_period.map { |items| items.count { |figure| !figure.respected? } },
          periodExcessHours: per_period.map { |items| excess_hours(items) },
          pivots: pivots(all),
          distribution: SlaFigures::BUCKETS.keys.map { |bucket| all.count { |figure| figure.bucket == bucket } },
          running: (running(type, status_ids) if current)
        }
      end

      # Share of respected delays, in percent; nil without any delay.
      def rate(items)
        (items.count(&:respected?) * 1000 / items.length).to_f / 10 if items.any?
      end

      # Average overrun of the overrun delays, in business hours.
      def excess_hours(items)
        overruns = items.reject(&:respected?)
        round(overruns.sum(&:excess) / 60.0 / overruns.length) if overruns.any?
      end

      def pivots(items)
        groups = items.group_by(&:pivot)
        figures.pivots(groups.keys).map do |key, name|
          {key: key, label: name, ended: groups[key].length, respected: groups[key].count(&:respected?), rate: rate(groups[key])}
        end
      end

      # Open issues whose clock runs now, by time used against the term.
      def running(type, status_ids)
        items = timelines.reject(&:closed?).select { |timeline| status_ids.include?(timeline.status.id) }.
          filter_map { |timeline| figures.for(timeline.id, type.id) }
        RISKS.transform_values { |buckets| items.count { |figure| buckets.include?(figure.bucket) } }
      end
    end
  end
end
