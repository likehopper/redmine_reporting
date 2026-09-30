# frozen_string_literal: true

module RedmineReporting
  module Reports
    # Time logged over the period, per collaborator and per activity.
    class Activity < Base
      def to_h
        by_user = time_entries.group_by(&:user).sort_by { |user, _| user.name }
        by_activity = time_entries.group_by(&:activity).sort_by(&:first)

        {
          userLabels: by_user.map { |user, _| user.name },
          userHours: by_user.map { |_, entries| hours(entries) },
          activityLabels: by_activity.map { |activity, _| activity.name },
          activityHours: by_activity.map { |_, entries| hours(entries) }
        }
      end

      private

      def hours(entries)
        round(entries.sum { |entry| entry.hours.to_f })
      end
    end
  end
end
