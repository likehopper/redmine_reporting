# frozen_string_literal: true

module RedmineReporting
  module Reports
    # Time logged over the period, per collaborator and per activity.
    class Activity < Base
      def to_h
        by_user = time_entries.group_by(&:user).sort_by { |user, _| user.name }
        by_activity = time_entries.group_by(&:activity).sort_by(&:first)

        by_user_activity = time_entries.group_by { |entry| [entry.user_id, entry.activity_id] }.transform_values { |entries| hours(entries) }

        {
          userIds: by_user.map { |user, _| user.id },
          activityIds: by_activity.map { |activity, _| activity.id },
          userActivityHours: by_activity.map do |activity, _|
            by_user.map { |user, _| by_user_activity.fetch([user.id, activity.id], 0.0) }
          end,
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
