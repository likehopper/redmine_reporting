# Redmine compatibility

The matrix targets Redmine 5.0.14, 5.1.13, 6.0.11, 6.1.4 and 7.0.1.
Redmine 7.1 has no stable release in the official release index as of 2026-09-30;
it is not advertised as supported. Re-run the matrix when a release is available.

## Validation

The release-hardening suite contains 90 unit, integration and browser tests.
The optional SLA coexistence case adds one test when that plugin is installed.
See the result table below for the exact runtimes validated after the fixes.

The tested application files are recorded in [runtime.sha256](runtime.sha256).
Verify them from the plugin directory with
`sha256sum -c test/compatibility/runtime.sha256`.
Results apply to this code snapshot, not a previously packaged or deployed copy.
The version-matrix snapshot differs only in indentation of `QueryDescription`;
the final SLA/PostgreSQL run matches every application checksum exactly.

## Verified results — 2026-09-30

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

GitHub Actions repeats the version, database, SLA and demo checks. The workflow is
prepared locally; its remote execution requires publishing the repository.
