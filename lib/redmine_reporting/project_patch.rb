# frozen_string_literal: true

module RedmineReporting
  # Reporting configuration belongs to its project and disappears with it.
  module ProjectPatch
    def self.included(base)
      base.has_one :reporting_project_setting, dependent: :destroy
      base.has_many :reporting_credit_policies, dependent: :destroy
    end
  end
end
