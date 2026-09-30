# frozen_string_literal: true

module RedmineReporting
  # Report families a project can display. Planned families are listed in the settings
  # so the configuration model is visible, but cannot be enabled until their charts exist.
  module Sections
    # A dashboard tab and the data it needs: :issues (issue tracking) and/or :time (time tracking).
    Tab = Struct.new(:id, :needs)

    Section = Struct.new(:id, :permission, :requires, :planned, :tabs, keyword_init: true) do
      def selectable?
        !planned
      end
    end

    RUN_TABS = [
      Tab.new("flow", [:issues]), Tab.new("activity", [:time]), Tab.new("consumption", [:time]),
      Tab.new("backlog", [:issues]), Tab.new("performance", [:issues])
    ].freeze

    ALL = [
      Section.new(id: "run", permission: :view_reporting, tabs: RUN_TABS),
      Section.new(id: "sla", permission: :view_reporting, requires: :sla, planned: true),
      Section.new(id: "build", permission: :view_reporting, planned: true),
      Section.new(id: "workload", permission: :view_reporting, planned: true)
    ].freeze

    def self.find(id)
      ALL.find { |section| section.id == id.to_s }
    end

    def self.selectable_ids
      ALL.select(&:selectable?).map(&:id)
    end

    # Whether the project has what the family needs (the SLA plugin configured for it, for instance).
    def self.available?(section, project)
      section.requires != :sla || SlaSource.new(project).configured?
    end

    def self.visible(project, user, setting)
      ALL.select do |section|
        section.selectable? && setting.section_enabled?(section.id) && available?(section, project) &&
          user.allowed_to?(section.permission, project)
      end
    end
  end
end
