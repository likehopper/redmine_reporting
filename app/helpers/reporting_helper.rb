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
  def render_api_reporting_credit_policy(api, policy)
    api.reporting_credit_policy do
      api.id policy.id
      api.project(id: policy.project_id, name: policy.project.name)
      api.tracker(id: policy.tracker_id, name: policy.tracker.name)
      api.name policy.name
      api.initial_credit_days policy.initial_credit_days.to_f
      api.anniversary_month policy.anniversary_month
      api.anniversary_day policy.anniversary_day
      api.active_from policy.active_from
      api.active_until policy.active_until
      api.enabled policy.enabled
      api.array :refills do
        policy.sorted_refills.each do |refill|
          api.refill do
            api.id refill.id
            api.month refill.month
            api.day refill.day
            api.credit_days refill.credit_days.to_f
            api.starts_on refill.starts_on
            api.ends_on refill.ends_on
          end
        end
      end
      api.created_on policy.created_at
      api.updated_on policy.updated_at
    end
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

  # "7,5" rather than Redmine's "7:30": a unit of conversion, not a duration.
  def reporting_hours(value)
    number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
  end

  # "+3j" / "-2j": a gap reads with its sign.
  def reporting_signed_days(value)
    value.positive? ? "+#{reporting_days(value)}" : reporting_days(value)
  end

  def reporting_days(value)
    l(:"reporting.summary.days", value: number_with_precision(value, precision: 1, strip_insignificant_zeros: true))
  end
end
