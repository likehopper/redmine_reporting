# frozen_string_literal: true

require "redmine"
require_relative "lib/redmine_reporting"

Redmine::Plugin.register :redmine_reporting do
  name "Redmine Reporting"
  author "Redmine Reporting contributors"
  description "Project reporting with configurable time-credit policies."
  version RedmineReporting::VERSION
  url "https://github.com/likehopper/redmine_reporting"

  requires_redmine version_or_higher: "5.0"

  menu :project_menu, :redmine_reporting,
    { controller: "reporting", action: "index" },
    caption: :label_reporting,
    param: :project_id

  project_module :reporting do
    permission :view_reporting, { reporting: [:index, :details] }, require: :member
    permission :manage_reporting, {
      reporting_settings: [:update],
      reporting_credit_policies: [:new, :create, :edit, :update, :destroy]
    }, require: :member
  end
end

# Redmine runs this file from its own to_prepare hook, on boot and after each code reload:
# a nested to_prepare block would never run in production.
IssueQuery.prepend(RedmineReporting::IssueQueryExtensions) unless IssueQuery < RedmineReporting::IssueQueryExtensions
TimeEntryQuery.prepend(RedmineReporting::TimeEntryQueryExtensions) unless TimeEntryQuery < RedmineReporting::TimeEntryQueryExtensions
Project.include(RedmineReporting::ProjectPatch) unless Project < RedmineReporting::ProjectPatch
ProjectsController.helper(RedmineReporting::ProjectsHelperPatch) unless ProjectsController._helpers < RedmineReporting::ProjectsHelperPatch
ProjectsController.helper(ReportingHelper) unless ProjectsController._helpers < ReportingHelper
