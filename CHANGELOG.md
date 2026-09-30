# Changelog

## 1.0.0 — Unreleased

Initial Run reporting release: issue flow, activity, time credits, backlog and
performance; project settings, subprojects, native Redmine filters and drilldowns;
English and French UI; bundled Chart.js.

Release hardening:

- Authorize report JSON and project credit scopes, not only visible tabs.
- Reconstruct backlog status from issue journals, including reopenings, with
  matching native issue-list filters and user time zones.
- Preserve the opening credit balance in the rolling twelve-month graph.
- Convert each project's consumption with its own inherited hours-per-day setting.
- Reject invalid dates and more than 600 periods before allocating report data.
- Keep demo accounts locked with random passwords, require explicit disposable
  development/test usage, reject unrelated projects and account collisions.
- Use right-hand legends on wide multi-series charts and bottom legends on small
  screens, preserving legend toggles and chart drilldowns.
- Move dashboard descriptions and links into DashboardPresenter with explicit
  dependencies; keep only five stateless formatting/icon helpers.
- Keep date boundaries in Ruby, presentation outside ReportingQuery, and inherited
  settings writes in the model; use prefix sums for historical spent time.
- Add regression/security/browser tests and a Docker/GitHub Actions matrix for
  Redmine 5.0–7.0, SQLite, PostgreSQL, MariaDB, MySQL and SLA coexistence.

SLA reports, Build & Projects and Workload & Team are outside this release.
