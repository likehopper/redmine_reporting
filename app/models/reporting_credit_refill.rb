# frozen_string_literal: true

class ReportingCreditRefill < (defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base)
  belongs_to :reporting_credit_policy

  validates :credit_days, numericality: { greater_than: 0 }
  validates :month, inclusion: { in: 1..12 }
  validates :day, inclusion: { in: 1..31 }
  validate :active_until_must_follow_active_from

  # Credit added on the refill dates of the range that fall within its own validity.
  def credit_days_between(first_day, last_day)
    RedmineReporting::YearlyDate.between(month, day, first_day, last_day).
      count { |date| RedmineReporting::YearlyDate.within?(date, starts_on, ends_on) } * credit_days.to_f
  end

  private

  def active_until_must_follow_active_from
    return if starts_on.blank? || ends_on.blank? || ends_on >= starts_on

    errors.add(:ends_on, :greater_than_or_equal_to, count: starts_on)
  end
end