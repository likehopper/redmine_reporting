# Configuration guide

From an installed plugin to a working dashboard, in nine steps. The screenshots come
from the browser test [`configuration_test.rb`](../test/documentation/configuration_test.rb),
run on the [demo data](../README.md#demo-data): a *Reporting Demo* project with two
subprojects, *Maintenance* and *Product*.

## 1. Check the installation

`Administration → Plugins` lists **Redmine Reporting**.

![Plugin list](screenshots/configuration/01-admin-plugins.png)

## 2. Grant the permissions

`Administration → Roles and permissions → <role>`, **Reporting** block:

- **View reporting**: open the dashboard;
- **Configure reporting**: edit the project's reporting settings and contracts.

![Role permissions](screenshots/configuration/02-role-permissions.png)

Charts also need Redmine's own permissions: *View issues* for issue charts, *View spent
time* for time charts.

## 3. Enable the module

`Project → Settings → Project`: tick **Reporting** under **Modules**, then save.

![Project modules](screenshots/configuration/03-project-modules.png)

The **Reporting** tab appears in the project menu.

![Project menu](screenshots/configuration/04-project-menu.png)

## 4. Configure the reports

`Project → Settings → Reporting`. The menu on the left opens one part of the settings at
a time; each part has its own **Save** button. By default, only **Run** is displayed, every
tracker counts, and a day is 8 hours.

![Default settings](screenshots/configuration/05-settings-default.png)

- **Displayed reports**: the dashboard's report families. *Run & Support (SLA)* can be enabled once the SLA plugin
  is configured for the project.
- **Time unit**: hours per day, to convert hours into days.
- **Run / Build trackers**:
  - Once a tracker is **Run**, Run reports count only Run trackers.
  - Build reports count only **Build** trackers.
  - Workload counts every tracker.
- **SLA statuses**: shown only when the SLA plugin is configured for the project; read-only.
- **Contracts**: see the next step.

The example enables every family, uses 7.5-hour days, and classifies *Bug* and *Support
request* as Run and *Feature request* as Build.

![Configured settings](screenshots/configuration/06-settings-filled.png)

## 5. Add a contract

Open **Contracts** and click **New contract**. A contract has dates of any length, the
trackers it covers and its credit, split into **envelopes**. The example covers *Bug* and
*Support request* for a year: 40 days of development on public issues, with a 10-day
amendment after six months, and 15 days of support.

![New contract](screenshots/configuration/07-contract-form.png)

Each logged hour goes to the envelope matching its activity and the issue's privacy;
time matching none, or without an issue, is outside the contract. A new contract starts
with a single envelope for all activities: that is enough for a plain time credit.

**Renew** prepares the next contract from the day after, with the same length, trackers
and envelopes. Ticking the box of an envelope carries its balance over, or deducts its
overrun.

![Renewal](screenshots/configuration/08-contract-renewal.png)

The list shows current, upcoming and finished contracts, with what each one consumed
and has left.

![Contract list](screenshots/configuration/09-contract-list.png)

The **Learn more** links open the plugin's help page, which every member allowed to view
reporting can read.

## 6. Subprojects

A subproject without its own settings uses its parent's. Saving the tab gives it its
own settings, from any of its parts. Contracts are never inherited: each project has its
own. With **Include subprojects**, a contract also counts its subprojects' time, unless a
subproject's own contract covers the same tracker on that date; subprojects' reports do
not show it.

![Inherited settings](screenshots/configuration/10-subproject-inherited.png)

## 7. Read the dashboard

Open **Reporting**. Choose a family tab, Redmine's native **Filters**, and the period and
grouping in **Options**.

### Run

The banner gives the period's issues and work: estimated, done, left to do.

**Issue flow**: issues created and closed per period.

![Issue flow](screenshots/configuration/11-run-flow.png)

**Activity**: time logged per collaborator and activity.

![Activity](screenshots/configuration/12-run-activity.png)

**Consumption**: for the displayed contracts, the balance at the start of the period,
what was granted, consumed and left, then a summary by contract and envelope. Time
outside contracts is shown apart.

![Consumption](screenshots/configuration/13-run-consumption.png)

**Backlog**: issues still open at the end of each period, and the time left.

![Backlog](screenshots/configuration/14-run-backlog.png)

**Performance**: velocity, resolution time and age of open issues.

![Performance](screenshots/configuration/15-run-performance.png)

### Build & Projects

Progress, overdue issues and effort by version, then burnup by version.

![Build & Projects](screenshots/configuration/16-build.png)

![Burnup by version](screenshots/configuration/17-build-burnup.png)

### Workload & Team

Open issues and remaining effort by assignee, and time logged per contributor.

![Workload](screenshots/configuration/18-workload.png)

## 8. Open the matching issues

A click on a bar, point, period label or banner figure opens the matching native Redmine
list, already filtered. There you can sort, export or save it as a query.

![Native issue list](screenshots/configuration/19-drilldown-issues.png)

## 9. Select contracts

The buttons above the reports filter the whole page: one contract, several, the time
outside contracts, or everything. **Private issues** includes, excludes or isolates them.

![Contract selection](screenshots/configuration/20-contract-selection.png)

The help page explains contracts, envelopes and renewal in the user's language.

![Help page](screenshots/configuration/21-help.png)

## Troubleshooting

| Symptom | Check |
|---|---|
| No **Reporting** tab | Step 3, then *View reporting* (step 2). |
| No **Reporting** settings tab | *Configure reporting* (step 2). |
| "No report is enabled for this project." | Select at least one family (step 4). |
| Activity or Consumption tab missing | *Time tracking* module and *View spent time*. |
| Issue tabs missing | *Issue tracking* module and *View issues*. |
| Build & Projects empty | Classify at least one tracker as Build (step 4). |
| Credit at 0 days | No contract runs during the period, or its project is not selected. |
| Time outside contract | Its tracker, date, activity or privacy matches no envelope, or it has no issue. |

## Regenerating the screenshots

```sh
bash test/documentation/run.sh [6.0.11|6.1.4|7.0.1]
```

This runs the test in a disposable container (SQLite, Chromium, default 6.1.4). It
updates `doc/screenshots/configuration/` and the README image. Figures depend on the
run date. The test is not part of `redmine:plugins:test`.
