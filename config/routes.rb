# frozen_string_literal: true

get "projects/:project_id/reporting", to: "reporting#index", as: "project_reporting"
get "projects/:project_id/reporting/details", to: "reporting#details", as: "project_reporting_details"

patch "projects/:project_id/reporting/settings", to: "reporting_settings#update", as: "project_reporting_settings"
scope "projects/:project_id/reporting", as: "project_reporting" do
  resources :credit_policies, controller: "reporting_credit_policies", only: [:new, :create, :edit, :update, :destroy]
end
