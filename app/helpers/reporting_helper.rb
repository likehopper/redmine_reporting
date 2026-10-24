# frozen_string_literal: true
# File: redmine_reporting/app/helpers/reporting_helper.rb
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

module ReportingHelper
  def render_api_reporting_credit_contract(api, contract)
    api.reporting_credit_contract do
      api.id contract.id
      api.project(id: contract.project_id, name: contract.project.name)
      api.name contract.name
      api.description contract.description
      api.starts_on contract.starts_on
      api.ends_on contract.ends_on
      api.include_subprojects contract.include_subprojects
      api.array :trackers do
        contract.trackers.each { |tracker| api.tracker(id: tracker.id, name: tracker.name) }
      end
      api.array :envelopes do
        contract.envelopes.each do |envelope|
          api.envelope do
            api.id envelope.id
            api.name envelope.name
            api.days envelope.days.to_f
            api.other_activities envelope.other_activities
            api.issue_privacy envelope.issue_privacy
            api.position envelope.position
            api.array :activities do
              envelope.activities.each { |activity| api.activity(id: activity.id, name: activity.name) }
            end
            api.array :movements do
              envelope.movements.each do |movement|
                api.movement do
                  api.id movement.id
                  api.date movement.date
                  api.days movement.days.to_f
                  api.comment movement.comment
                  api.source_envelope_id movement.source_envelope_id
                end
              end
            end
          end
        end
      end
      api.created_on contract.created_at
      api.updated_on contract.updated_at
    end
  end

  def reporting_dates(from, to)
    l(:"reporting.contracts.dates_value", from: format_date(from), to: format_date(to))
  end

  # A short explanation shown on hover or focus, without leaving the page.
  def reporting_tip(text)
    tag.span("?", class: "reporting-tip", title: text, tabindex: 0, role: "note", aria: {label: text})
  end

  # Link to a section of the help page, readable with the sole permission to view reporting.
  def reporting_help_link(project, anchor)
    link_to l(:"reporting.help.more"), project_reporting_help_path(project_id: project, anchor: anchor), class: "reporting-help-link",
            target: "_blank", rel: "noopener"
  end

  # The report with one filter replaced (nil removes it), other filters and dates kept.
  def reporting_filter_path(field, values)
    parameters = @query.as_params.deep_dup
    fields = Array(parameters[:f]) - [field]
    parameters[:op] = (parameters[:op] || {}).except(field)
    parameters[:v] = (parameters[:v] || {}).except(field)
    if values
      fields << field
      parameters[:op][field] = "="
      parameters[:v][field] = values
    end
    project_reporting_path(project_id: @project, **parameters, f: fields.presence || [""], from: @date_from, to: @date_to,
                           grouping: @grouping, tab: @active_tab)
  end

  # Contract buttons add up. From the full selection, a button shows that contract alone;
  # back to everything, or to nothing, the filter goes.
  def reporting_contract_selection(all)
    return all unless @query.has_filter?("reporting_contract")

    values = @query.values_for("reporting_contract").map(&:to_s)
    @query.operator_for("reporting_contract") == "=" ? all & values : all - values
  end

  def reporting_contract_toggle_path(all, key)
    current = reporting_contract_selection(all)
    selected = current == all ? [key] : (current.include?(key) ? current - [key] : current + [key])
    reporting_filter_path("reporting_contract", selected.empty? || selected.sort == all.sort ? nil : all & selected)
  end

  def reporting_privacy
    return "all" unless @query.has_filter?("reporting_private")

    values = @query.values_for("reporting_private").map(&:to_s)
    private_only = values == ["1"]
    private_only = !private_only if @query.operator_for("reporting_private") == "!"
    values.sort == %w[0 1] ? "all" : (private_only ? "only" : "exclude")
  end

  # How a finished contract or envelope closed: carried over, expired, or overrun not taken over.
  def reporting_closing(item)
    closing, carried = item[:closing].to_f, item[:carried].to_f
    parts = []
    parts << l(:"reporting.consumption.closing_carried", days: reporting_days(carried)) if carried.positive?
    parts << l(:"reporting.consumption.closing_debt_taken", days: reporting_days(-carried)) if carried.negative?
    left = closing - carried
    parts << l(:"reporting.consumption.closing_expired", days: reporting_days(left)) if left.positive?
    parts << l(:"reporting.consumption.closing_debt", days: reporting_days(-left)) if left.negative?
    parts.empty? ? l(:"reporting.consumption.closing_even") : safe_join(parts, tag.br)
  end

  # Redmine 6 draws icons from an SVG sprite; older versions use the CSS class alone.
  def reporting_icon(name, text)
    respond_to?(:sprite_icon) ? sprite_icon(name, text) : text
  end

  # "7,5" rather than Redmine's "7:30": a unit of conversion, not a duration.
  def reporting_hours(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  # "+3j" / "-2j": a gap reads with its sign.
  def reporting_signed_days(value)
    value.positive? ? "+#{reporting_days(value)}" : reporting_days(value)
  end

  # "40" rather than "40.0" in number inputs.
  def reporting_number(value)
    return if value.nil?

    (value.to_f % 1).zero? ? value.to_i : value.to_f
  end

  def reporting_days(value)
    l(:"reporting.summary.days", value: number_with_precision(value, precision: 1, strip_insignificant_zeros: true))
  end
end
