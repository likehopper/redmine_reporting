# Publishing 1.0.0

The code is a release candidate under GPL-2.0-or-later. Its public repository is
https://github.com/likehopper/redmine_reporting. Publish a tagged stable release
after the compatibility matrix passes.

1. Retain the GPL license in `LICENSE` and the version-or-later notice in README.
   Retain `assets/javascripts/Chart.js.LICENSE.md` for the bundled MIT dependency.
2. Set the public repository/homepage in Redmine's plugin registry. Installation
   from an archive already works without a Git URL.
3. Run the documented version, database, SLA and demo checks. Record their results
   in `test/compatibility/README.md` and refresh `runtime.sha256` when code changes.
4. Commit the validated tree, date the changelog, then create the `v1.0.0` tag.
5. Create a reproducible archive from that tag:

   ```sh
   mkdir -p dist
   git archive --format=tar --prefix=redmine_reporting/ v1.0.0 | gzip -n > dist/redmine_reporting-1.0.0.tar.gz
   sha256sum dist/redmine_reporting-1.0.0.tar.gz
   ```

The local `*-candidate.tar.gz` archive, if present, is for review and is not a
published release. GitHub Actions is configured but has not run remotely before
the repository is published.

## Suggested registry description

Redmine Reporting adds project dashboards for issue flow, activity, time-credit
consumption, backlog and performance. Reports include subprojects, respect Redmine
permissions and link to native filtered lists. Available in English and French.

## Release scope

Run reports are included. SLA reports, Build & Projects and Workload & Team remain
future features. Redmine 7.1 is not certified; add it only after an available stable
release has passed the matrix. Compatibility claims refer to the exact tested
patch and runtime combinations, not every possible installation.
