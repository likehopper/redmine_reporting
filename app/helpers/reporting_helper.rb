# frozen_string_literal: true

module ReportingHelper
  # What the active tab's charts count, with the dates each one relies on.
  def reporting_tab_scope(tab, report)
    values = {from: format_date(@date_from), to: format_date(@date_to), grouping: l("label_reporting_grouping_#{@grouping}").downcase,
              hours: reporting_hours_per_day}
    if tab == "consumption"
      contract_start = report.dig(:consumption, :contract, :periodStarts)&.first
      values[:contract] = contract_start ? l(:"reporting.scope.consumption_contract", date: format_date(Date.iso8601(contract_start))) : ""
    end
    l(:"reporting.scope.#{tab}", **values)
  end

  # "1 juillet" / "July 1" for yearly anniversaries and refills.
  def reporting_day_of_year(month, day)
    l(:"reporting.settings.day_of_year", day: day, month: month_name(month))
  end

  def reporting_validity(from, to)
    if from && to then l(:"reporting.settings.validity_between", from: format_date(from), to: format_date(to))
    elsif from then l(:"reporting.settings.validity_from", from: format_date(from))
    elsif to then l(:"reporting.settings.validity_until", to: format_date(to))
    else l(:"reporting.settings.validity_always")
    end
  end

  # Redmine 6 draws icons from an SVG sprite; older versions use the CSS class alone.
  def reporting_icon(name, text)
    respond_to?(:sprite_icon) ? sprite_icon(name, text) : text
  end

  def reporting_hours_per_day
    reporting_hours(@reporting_setting&.hours_per_day || ReportingProjectSetting::DEFAULT_HOURS_PER_DAY)
  end

  # "7,5" rather than Redmine's "7:30": a unit of conversion, not a duration.
  def reporting_hours(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  def reporting_days(value)
    l(:"reporting.summary.days", value: number_with_precision(value, precision: 1, strip_insignificant_zeros: true))
  end
end
