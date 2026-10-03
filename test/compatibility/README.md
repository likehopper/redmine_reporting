# Redmine compatibility

The matrix targets Redmine 5.0.14, 5.1.13, 6.0.11, 6.1.4 and 7.0.1.
Redmine 7.1 has no stable release in the official release index as of 2026-09-30;
it is not advertised as supported. Re-run the matrix when a release is available.

## Validation

## Release 1.2.1 validation — 2026-10-03

GitHub Actions passed all ten compatibility jobs for application commit
`92753d2b66c67d687deab396cdc71cb18c1c12df` in [PR #4](https://github.com/likehopper/redmine_reporting/pull/4):
Redmine 5.0.14, 5.1.13, 6.0.11, 6.1.4 and 7.0.1 with SQLite; Redmine 6.1.4
with PostgreSQL 16, MySQL 8.0 and MariaDB 10.11; SLA coexistence on PostgreSQL;
and the disposable demo-data smoke check. Browser tests are included.

The release-finalization changes only date the changelog and update release
validation documentation. Runtime fingerprints match the application files.


Test counts are recorded per validated snapshot below.
The optional SLA coexistence case adds one test when that plugin is installed.
See the result table below for the exact runtimes validated after the fixes.

The tested application files are recorded in [runtime.sha256](runtime.sha256).
Verify them from the plugin directory with
`sha256sum -c test/compatibility/runtime.sha256`.
Results apply to this code snapshot, not a previously packaged or deployed copy.
The initial hardening results below describe commit `1fbc347`.
The subsequent DashboardPresenter refactor changes presentation only; its
verification is recorded separately below.

## RUN/BUILD split and historical Burnup verification — 2026-10-02

The combined branch passed migrations, uninstall/reinstall and the full suite,
including Chromium. All runs completed without failures, errors or skips.

| Redmine | Database | Tests | Assertions | Result |
|---|---|---:|---:|---|
| 5.0.14 | SQLite | 117 | 1001 | PASS |
| 7.0.1 | SQLite | 117 | 1011 | PASS |
| 6.1.4 | PostgreSQL 16 | 117 | 1003 | PASS |
| 6.1.4 | MySQL 8.0, strict SQL mode | 117 | 1003 | PASS |
| 6.1.4 | MariaDB 10.11, strict SQL mode | 117 | 1003 | PASS |

Before integration, Redmine 6.1.4/SQLite passed the ratio branch (112 tests,
955 assertions) and the Burnup branch (109 tests, 903 assertions) separately.
Coverage includes all four time categories and native drilldowns, historical
version moves/unassignment, closure/reopening, timezone boundaries, version
filters retaining moved-out issues, future periods and visibility.
Redmine 5.1/6.0 and SLA coexistence were not rerun for these changes.
Historical runtime checksums still describe their earlier snapshot.

## Workload & Team verification — 2026-10-02

The full suite passed with SQLite and Chromium, including installation and
uninstall/reinstall checks:

| Redmine | Tests | Assertions | Result |
|---|---:|---:|---|
| 5.0.14 | 111 | 929 | PASS |
| 6.1.4 | 111 | 931 | PASS |
| 7.0.1 | 111 | 939 | PASS |

No failures, errors or skips. Added coverage includes current assignments versus
period contributions, groups, locked assignees, missing estimates, overruns,
unassigned issues, issue-only/time-only access, private projects/issues,
project-level effort permissions, empty filters and browser drilldowns.
Redmine 5.1/6.0 and external databases were not rerun for this change.
The historical runtime checksum file still describes its earlier snapshot.

## Build & Projects verification — 2026-10-02

The Build charts and family navigation passed the complete suite with SQLite and
Chromium, including installation and uninstall/reinstall checks:

| Redmine | Tests | Assertions | Result |
|---|---:|---:|---|
| 5.0.14 | 104 | 854 | PASS |
| 6.1.4 | 104 | 856 | PASS |
| 7.0.1 | 104 | 864 | PASS |

No failures, errors or skips. Coverage includes empty Build classification,
version drilldowns, excluded unassigned time, overruns, project/time permissions,
Build-only projects, browser rendering and chart clicks. Redmine 5.1/6.0 and
external databases were not rerun for this change. The historical runtime checksum
file below still describes its earlier snapshot.

## Initial hardening results — 2026-09-30

All runs below passed installation, rollback/reinstallation and the complete suite,
including seven Chromium system tests, with no failures, errors or skips.

| Redmine | Ruby | Rails | Tests | Assertions | Result |
|---|---|---|---:|---:|---|
| 5.0.14 | 3.1.7 | 6.1.7.10 | 90 | 721 | PASS |
| 5.1.13 | 3.2.11 | 6.1.7.10 | 90 | 721 | PASS |
| 6.0.11 | 3.3.12 | 7.2.3.2 | 90 | 723 | PASS |
| 6.1.4 | 3.4.11 | 7.2.3.2 | 90 | 723 | PASS |
| 7.0.1 | 4.0.7 | 8.1.3.1 | 90 | 729 | PASS |

Additional Redmine 6.1.4 checks:

| Database / configuration | Tests | Assertions | Result |
|---|---:|---:|---|
| PostgreSQL 16 | 90 | 723 | PASS |
| MariaDB 10.11, strict SQL mode | 90 | 723 | PASS |
| MySQL 8.0, strict SQL mode | 90 | 723 | PASS |
| PostgreSQL 16 + redmine_sla v3.0.5 | 91 | 732 | PASS |

The demo smoke check passed twice with stable counts: 3 projects, 355 issues and
894 time entries, with all generated accounts locked. The optional volume check
also passed (5,000 issues and 60,000 entries; see measurements below).

## DashboardPresenter verification — 2026-09-30

After extracting dashboard descriptions, units and links into an object with
explicit dependencies, the complete suite was rerun on these representative
Redmine/Rails generations, using SQLite and Chromium:

| Redmine | Tests | Assertions | Result |
|---|---:|---:|---|
| 5.0.14 | 90 | 721 | PASS |
| 6.1.4 | 90 | 723 | PASS |
| 7.0.1 | 90 | 729 | PASS |

No failures, errors or skips. These results describe the presenter snapshot before
the later consumption and nested-account changes. Redmine 5.1/6.0 and the external database/SLA configurations
were validated before this presentation-only refactor, as recorded above; they
were not rerun for this change. No database, query or report-calculation code changed.

## Period-based consumption and banner verification — 2026-10-01

After computing consumption over the selected period (credit carried over to its
first day, one credit account per subproject) and basing the banner's estimated,
done and left-to-do figures on the same filtered issues, the complete suite was
rerun on every Redmine version, using SQLite and Chromium:

| Redmine | Ruby | Rails | Tests | Assertions | Result |
|---|---|---|---:|---:|---|
| 5.0.14 | 3.1.7 | 6.1.7.10 | 97 | 784 | PASS |
| 5.1.13 | 3.2.11 | 6.1.7.10 | 97 | 784 | PASS |
| 6.0.11 | 3.3.12 | 7.2.3.2 | 97 | 786 | PASS |
| 6.1.4 | 3.4.11 | 7.2.3.2 | 97 | 786 | PASS |
| 7.0.1 | 4.0.7 | 8.1.3.1 | 97 | 794 | PASS |

No failures, errors or skips. These results describe the period-based consumption
snapshot before the final nested-account correction. See the final verification
below for the current application manifest.

## Pre-publication verification — 2026-10-01

The final review reran the complete 97-test suite on all five Redmine versions,
PostgreSQL and SLA coexistence (98 tests), plus the disposable demo check, with
no failures, errors or skips. It also corrected nested project credit aggregation
and added a regression test: the final 98-test suite passed on Redmine 6.1.4 with
SQLite, MariaDB 10.11 and MySQL 8.0. Those final snapshots match `runtime.sha256`.
The test includes distinct collaborators with identical names and real chart clicks.

The public [compatibility workflow](https://github.com/likehopper/redmine_reporting/actions/workflows/compatibility.yml)
runs every version/database/SLA/demo combination again from the published source.
Local logs and screenshots are retained in the ignored `dist/validation` and
`dist/previews` directories; neither is required to install the plugin.

## Reproduce

From the plugin directory, with Docker and internet access:

```sh
bash test/compatibility/run.sh
# Or select versions:
bash test/compatibility/run.sh 5.0.14 7.0.1
```

The script builds disposable test images from official Redmine images, installs
Chromium and its matching driver, and tests a frozen copy of this plugin. Each
container has a separate SQLite database and no published port. Only the
screenshot artifact directory is mounted writable. Existing Redmine instances and databases are not used. Containers are
removed after execution; images remain cached for the next run.

The exact 5.0.14 and 5.1.13 Docker tags are unavailable, so those entries use the
branch image's Ruby runtime and download the exact official Redmine archive,
checking its published SHA-256 before extraction. Dependencies are resolved by
Bundler using that release's own Gemfile. The runner checks the loaded Redmine
version. `COMPAT_IMAGE_PREFIX` optionally selects already prepared test images
that provide the appropriate Ruby, test dependencies, Chromium, driver and curl.

The printed results directory contains the snapshot, its `source.sha256`, image
build logs, complete test logs and `results.txt`. Any failed entry makes the
script exit nonzero. Bundler needs network access; application charts use the
plugin's bundled Chart.js.

## Scope

Every entry checks fresh installation, all plugin migrations, uninstall/reinstall,
unit and integration tests, plus actual browser tests. These cover calculations,
JSON settings persistence, project configuration, permissions, native filters and
lists, chart rendering and clicks, and French/English labels.

The version matrix uses SQLite and the stock Redmine theme. Additional Redmine
6.1.4 runs cover PostgreSQL 16, MariaDB 10.11 and MySQL 8.0 in strict SQL mode,
and redmine_sla v3.0.5 on PostgreSQL. This does not certify every earlier patch,
every supported Ruby, every database/version pairing, custom themes or other plugins. Redmine 5 requires Ruby 3.1 or newer for this plugin's syntax;
use a Ruby version supported by the selected Redmine release.

The test harness accommodates Rails 6.1's single fixture directory and Redmine
5.0's explicit fixture loading. On 5.0 it selects the OS-provided Chrome driver
instead of the old webdrivers gem's obsolete download service. Browser clicks use
viewport coordinates, avoiding Selenium 3/4's different element-offset semantics.

Official release source: https://www.redmine.org/releases/

## Database, SLA, demo and volume checks

```sh
COMPAT_DB=postgres bash test/compatibility/run.sh 6.1.4
COMPAT_DB=mariadb bash test/compatibility/run.sh 6.1.4
COMPAT_DB=mysql bash test/compatibility/run.sh 6.1.4
COMPAT_DB=postgres COMPAT_SLA_PATH=/path/to/redmine_sla bash test/compatibility/run.sh 6.1.4
REPORTING_DEMO_SMOKE=1 bash test/compatibility/run.sh 6.1.4
REPORTING_BENCHMARK=1 bash test/compatibility/run.sh 6.1.4
```

External-database runs accept one Redmine version, defaulting to 6.1.4. They create
an isolated Docker network and database container without published ports, and
remove both on exit. PostgreSQL, MariaDB and MySQL are tested separately. SLA does
not support SQLite. Only the explicitly supplied SLA checkout is mounted.

The demo check replaces the ordinary suite: on a fresh migrated database with
Redmine default data, it generates twice, checks stable record counts and verifies
that all generated accounts are locked. It never uses an existing database.

The optional volume test creates 5,000 issues and 60,000 time entries, warms the
report once, then measures three requests. On a shared host (2-CPU container limit),
the measured requests took 6.3–8.9 seconds, each with 15 uncached SQL queries and
about 3.48 million Ruby object allocations. These are observations under concurrent
test load, not a production latency guarantee or a measured before/after speedup.
Reports still load visible records into memory; large installations should profile
their actual data volume. No cache with uncertain permission invalidation is added.

GitHub Actions repeats the version, database, SLA and demo checks. Results are available in the repository’s Actions tab.

## License header maintenance — 2026-10-01

The runtime manifest was refreshed after adding license and source-path comments.
Removing each inserted header reproduces the previous source byte for byte;
no application behavior was changed.
