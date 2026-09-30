# frozen_string_literal: true

module RedmineReporting
  # What the reporting scope lets the user see. Redmine only grants a permission where its
  # module is enabled, so this follows both the project modules (issue tracking, time
  # tracking) and the user's roles, on any project of the reporting subtree.
  class Capabilities
    PERMISSIONS = {issues: :view_issues, time: :view_time_entries}.freeze

    def initialize(user, projects)
      projects = projects.to_a
      @granted = PERMISSIONS.transform_values { |permission| projects.any? { |project| user.allowed_to?(permission, project) } }
    end

    def issues?
      @granted[:issues]
    end

    def time?
      @granted[:time]
    end

    def any?
      @granted.values.any?
    end

    def allows?(tab)
      tab.needs.all? { |need| @granted[need] }
    end

    def tabs(section)
      section.tabs.select { |tab| allows?(tab) }.map(&:id)
    end
  end
end
