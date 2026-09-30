# frozen_string_literal: true

# Reuse Redmine's filter widgets, parameter format and SQL operators.
# Reporting dates are kept separate because each chart has its own date axis.
class ReportingQuery < Query
  self.queried_class = Issue
  self.view_permission = :view_reporting

  LEGACY_FILTERS = {
    project_ids: "project_id", tracker_ids: "tracker_id",
    status_ids: "status_id", priority_ids: "priority_id",
    version_ids: "fixed_version_id"
  }.freeze

  validate :validate_reporting_operators

  # Trackers of the Run perimeter, from the project's reporting settings; nil counts every tracker.
  attr_accessor :run_tracker_ids

  def initialize(attributes = nil, *args)
    super
    self.filters ||= {}
  end

  def initialize_available_filters
    add_available_filter "project_id", type: :list, values: -> { visible_projects.map { |project| [project.name, project.id.to_s] } }
    add_available_filter "tracker_id", type: :list, values: -> { tracker_scope.map { |tracker| [tracker.name, tracker.id.to_s] } }
    add_available_filter "status_id", type: :list, values: -> { IssueStatus.sorted.map { |status| [status.name, status.id.to_s] } }
    add_available_filter "priority_id", type: :list, values: -> { IssuePriority.active.sorted.map { |priority| [priority.name, priority.id.to_s] } }
    add_available_filter "fixed_version_id", type: :list_optional, values: lambda {
      Version.visible(reporting_user).where(project_id: visible_projects.select(:id)).includes(:project).
        order(:project_id, :name).map { |version| ["#{version.project.name} · #{version.name}", version.id.to_s] }
    }
  end

  def build_from_params(params, defaults = {})
    # The route's project identifier is context, not a numeric issue filter.
    super(params.except(:project_id, "project_id"), defaults)
    # Keep existing report bookmarks working; native parameters take precedence.
    unless params[:f] || params[:fields]
      LEGACY_FILTERS.each do |parameter, field|
        next unless params.key?(parameter)

        values = Array(params[parameter]).flat_map { |value| value.to_s.split(",") }.reject(&:blank?)
        add_filter(field, "=", values) if values.any?
      end
    end
    self
  end

  def as_params
    # Charts have no columns or sorting; serialize only their native filters.
    super.slice(:f, :op, :v, :set_filter).reverse_merge(f: [""])
  end

  def visible_projects
    @visible_projects ||= project ? project.self_and_descendants.visible(reporting_user).order(:lft) : Project.none
  end

  def selected_projects
    return Project.none unless valid?

    project_scope = visible_projects
    if has_filter?("project_id")
      project_scope = project_scope.where(sql_for_field("project_id", operator_for("project_id"), values_for("project_id"), Project.table_name, "id"))
    end
    project_scope
  end

  def tracker_scope
    Tracker.where(id: Project.where(id: visible_projects.select(:id)).joins(:trackers).select("trackers.id")).sorted
  end

  def selected_tracker_ids
    return [] unless valid?

    scope = tracker_scope
    scope = scope.where(id: run_tracker_ids) if run_tracker_ids.present?
    if has_filter?("tracker_id")
      scope = scope.where(sql_for_field("tracker_id", operator_for("tracker_id"), values_for("tracker_id"), Tracker.table_name, "id"))
    end
    scope.pluck(:id)
  end

  def issue_scope
    return Issue.none unless valid?

    scope = Issue.visible(reporting_user).where(project_id: selected_projects.select(:id)).where(statement)
    run_tracker_ids.present? ? scope.where(tracker_id: run_tracker_ids) : scope
  end

  def tracker_restricted?
    has_filter?("tracker_id") || run_tracker_ids.present?
  end

  def time_entry_scope
    return TimeEntry.none unless valid?

    scope = TimeEntry.visible(reporting_user).where(project_id: selected_projects.select(:id))
    # Unassigned time entries remain included until an issue filter is applied; the Run
    # perimeter alone keeps them, as it only sorts issues out.
    if filters.keys.any? { |field| field != "project_id" }
      scope.where(issue_id: issue_scope.select(:id))
    elsif run_tracker_ids.present?
      scope.where(issue_id: nil).or(scope.where(issue_id: issue_scope.select(:id)))
    else
      scope
    end
  end

  def project_statement
    # The explicit visible subtree above is independent of Redmine's issue-list preference.
    nil
  end

  private

  def reporting_user
    user || User.current
  end

  def validate_reporting_operators
    filters.each_key do |field|
      unless available_filters.key?(field) && operators_by_filter_type.fetch(type_for(field), []).include?(operator_for(field))
        errors.add(:base, l(:label_filter_plural) + " " + l("activerecord.errors.messages.invalid"))
      end
    end
  end
end
