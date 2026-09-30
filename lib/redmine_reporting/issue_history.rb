# frozen_string_literal: true

module RedmineReporting
  # Status transitions, including reopenings. Missing history falls back to the current
  # status and last closure date; deleted status definitions use the same fallback.
  class IssueHistory
    def initialize(issue, user, events = [], closed_status_ids = IssueStatus.where(is_closed: true).ids, status_ids = IssueStatus.ids)
      @issue, @user, @events, @closed_ids, @status_ids = issue, user, events, closed_status_ids, status_ids
    end

    def open_on?(date)
      event = @events.reverse.find { |time, _, _| @user.time_to_date(time) <= date }
      status = event ? event[2] : @events.first&.[](1)
      return !@closed_ids.include?(status.to_i) if status.present? && @status_ids.include?(status.to_i)

      !@issue.closed? || (@issue.closed_on && @user.time_to_date(@issue.closed_on) > date)
    end

    # Correlated SQL keeps native pagination/exports and never materializes issue IDs.
    # Both Ruby and SQL use the last transition before the viewer's end of day.
    def self.sql_open_on(date, user)
      connection = Issue.connection
      tomorrow = date + 1
      cutoff = user.time_zone ? user.time_zone.local(tomorrow.year, tomorrow.month, tomorrow.day) : Time.local(tomorrow.year, tomorrow.month, tomorrow.day)
      cutoff = connection.quote(cutoff.utc)
      source = "FROM journal_details rhd INNER JOIN journals rhj ON rhj.id = rhd.journal_id " \
        "WHERE rhj.journalized_type = 'Issue' AND rhj.journalized_id = issues.id " \
        "AND rhd.property = 'attr' AND rhd.prop_key = 'status_id'"
      previous = "SELECT rhd.value #{source} AND rhj.created_on < #{cutoff} ORDER BY rhj.created_on DESC, rhj.id DESC, rhd.id DESC LIMIT 1"
      initial = "SELECT rhd.old_value #{source} ORDER BY rhj.created_on ASC, rhj.id ASC, rhd.id ASC LIMIT 1"
      cast = connection.adapter_name.downcase.include?("mysql") ? "CHAR" : "VARCHAR"
      historical = "SELECT rhs.is_closed FROM issue_statuses rhs WHERE CAST(rhs.id AS #{cast}) = COALESCE((#{previous}), (#{initial}))"
      fallback = "CASE WHEN issues.closed_on >= #{cutoff} THEN #{connection.quoted_false} ELSE (SELECT rcs.is_closed FROM issue_statuses rcs WHERE rcs.id = issues.status_id) END"
      "COALESCE((#{historical}), (#{fallback})) = #{connection.quoted_false}"
    end
  end
end
