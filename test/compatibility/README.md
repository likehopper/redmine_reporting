# Redmine compatibility

The matrix targets Redmine 5.0.14, 5.1.13, 6.0.11, 6.1.4 and 7.0.1.
Redmine 7.1 has no stable release in the official release index as of 2026-09-30;
it is not advertised as supported. Re-run the matrix when a release is available.

## Verified results — 2026-09-30

All entries passed installation, rollback/reinstallation and the complete test
suite, including all five Chromium system tests. No failures, errors or skips.

| Redmine | Ruby | Rails | Tests | Assertions | Result |
|---|---|---|---:|---:|---|
| 5.0.14 | 3.1.7 | 6.1.7.10 | 77 | 662 | PASS |
| 5.1.13 | 3.2.11 | 6.1.7.10 | 77 | 662 | PASS |
| 6.0.11 | 3.3.12 | 7.2.3.2 | 77 | 663 | PASS |
| 6.1.4 | 3.4.11 | 7.2.3.2 | 77 | 663 | PASS |
| 7.0.1 | 4.0.7 | 8.1.3.1 | 77 | 666 | PASS |

The tested application files are recorded in [runtime.sha256](runtime.sha256).
Verify them from the plugin directory with
`sha256sum -c test/compatibility/runtime.sha256`.
Results apply to this code snapshot, not a previously packaged or deployed copy.

## Reproduce

From the plugin directory, with Docker and internet access:

```sh
bash test/compatibility/run.sh
# Or select versions:
bash test/compatibility/run.sh 5.0.14 7.0.1
```

The script builds disposable test images from official Redmine images, installs
Chromium and its matching driver, and tests a frozen copy of this plugin. Each
container has a separate SQLite database, no published port and no writable host
mount. Existing Redmine instances and databases are not used. Containers are
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

This validates the exact patch/runtime combinations below using SQLite and the
stock Redmine theme, without other plugins. It does not certify every earlier
patch, every supported Ruby, PostgreSQL/MySQL/MariaDB, custom themes or interactions
with other plugins. Redmine 5 requires Ruby 3.1 or newer for this plugin's syntax;
use a Ruby version supported by the selected Redmine release.

The test harness accommodates Rails 6.1's single fixture directory and Redmine
5.0's explicit fixture loading. On 5.0 it selects the OS-provided Chrome driver
instead of the old webdrivers gem's obsolete download service. Browser clicks use
viewport coordinates, avoiding Selenium 3/4's different element-offset semantics.

Official release source: https://www.redmine.org/releases/
