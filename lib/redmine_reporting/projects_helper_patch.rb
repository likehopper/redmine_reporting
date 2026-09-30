# frozen_string_literal: true

module RedmineReporting
  # Adds the "Reporting" tab to the project settings.
  module ProjectsHelperPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:reporting) && User.current.allowed_to?(:manage_reporting, @project)
        tabs << {name: "reporting", action: :manage_reporting, partial: "reporting_settings/show", label: :label_reporting}
      end
      tabs
    end
  end
end
