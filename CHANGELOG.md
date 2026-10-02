# Changelog

## 1.0.0 — Unreleased

Initial Run, Build and Workload reporting release: issue flow, activity, time credits, backlog and
performance; project settings, subprojects, native Redmine filters and drilldowns;
English and French UI; bundled Chart.js.

Build & Projects:

- Enable the Build family with its own tracker scope; an empty classification
  stays empty and excludes unassigned time.
- Show current open/closed issues, overdue issues and effort by version, including
  unversioned issues, with native issue-list drilldowns and permission-aware time data.
- Preserve the family when applying filters and opening detail lists; support
  projects that enable Build without Run.

Workload & Team:

- Show current open issues and calculated remaining effort by assignee, including
  groups, locked users and unassigned issues; flag missing estimates.
- Show period-based logged time by contributor across all trackers, with native
  list drilldowns using identities rather than display names.
- Respect issue/time visibility independently, including time-only configurations
  and project-level restrictions on remaining-effort calculations and their lists.
- Keep capacity planning out of this first version; no availability is inferred.

Release hardening:

- Authorize report JSON and project credit scopes, not only visible tabs.
- Reconstruct backlog status from issue journals, including reopenings, with
  matching native issue-list filters and user time zones.
- Compute consumption over the selected period: credit carried over to its first
  day, credits granted in it, time charged over it, credit left at its end. Time
  logged before the contract start is not charged.
- Keep independent credit balances and contract starts at every depth of the project tree.
- Treat each subproject as a credit account of its own and add accounts up, so the
  summary by project, the totals and each subproject's report agree.
- Separate the provider banner from the client consumption figures, with distinct
  labels. The banner's estimated, done and left-to-do figures cover the same filtered
  issues: estimated − done = left to do (open issues) + gap on closed issues.
- Convert each project's consumption with its own inherited hours-per-day setting.
- Reject invalid dates and more than 600 periods before allocating report data.
- Keep demo accounts locked with random passwords, require explicit disposable
  development/test usage, reject unrelated projects and account collisions.
- Keep flow/backlog legends below charts, with sequential flow numbering 1.1–1.6.
- Split collaborator bars by activity with shared colors, hour tooltips and exact
  collaborator/activity drilldowns, including distinct users with the same name.
- Explain consumption legends on hover and add descriptive chart subtitles.
- Move dashboard descriptions and links into DashboardPresenter with explicit
  dependencies; keep formatting/icon helpers independent of controller state.
- Keep date boundaries in Ruby, presentation outside ReportingQuery, and inherited
  settings writes in the model; use prefix sums for historical spent time.
- Add regression/security/browser tests and a Docker/GitHub Actions matrix for
  Redmine 5.0–7.0, SQLite, PostgreSQL, MariaDB, MySQL and SLA coexistence.

SLA reports are outside this release.
