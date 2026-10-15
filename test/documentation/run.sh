#!/usr/bin/env bash
# File: redmine_reporting/test/documentation/run.sh
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
# Usage: bash test/documentation/run.sh [6.1.4]
# Regenerates doc/screenshots/configuration in a disposable container and database.
set -euo pipefail
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
version="${1:-6.1.4}"
case "$version" in
  6.0.11|6.1.4|7.0.1) base=redmine:$version ;;
  *) printf 'Unsupported Redmine version: %s\n' "$version" >&2; exit 2 ;;
esac
results=$(mktemp -d "${TMPDIR:-/tmp}/redmine-reporting-doc.XXXXXX")
mkdir "$results/plugin" "$results/screenshots"
tar -C "$plugin_root" --exclude=.git --exclude=dist -cf - . | tar -C "$results/plugin" -xf -
printf 'Logs: %s\n' "$results"
image="${COMPAT_IMAGE_PREFIX:-reporting-compat}:$version"
if [ -z "${COMPAT_IMAGE_PREFIX:-}" ]; then
  docker build --build-arg "REDMINE_IMAGE=$base" -t "$image" "$plugin_root/test/compatibility" > "$results/build.log" 2>&1
fi
docker run --rm --cpus=2 --memory=2g --entrypoint sh \
  -v "$results/plugin:/plugin:ro" -v "$results/screenshots:/screenshots" "$image" -c '
set -eu
# Section titles use emoji: without a color emoji font, Chromium draws empty boxes.
(apt-get update && apt-get install -y --no-install-recommends fonts-noto-color-emoji) > /dev/null
rm -rf plugins/redmine_sla plugins/redmine_reporting
cp -a /plugin plugins/redmine_reporting
printf "test:\n  adapter: sqlite3\n  database: db/reporting_doc.sqlite3\n" > config/database.yml
echo "Rails.application.config.active_record.schema_format = :ruby" > config/initializers/reporting_test_schema.rb
export RAILS_ENV=test CHROMEDRIVER_PATH=/usr/bin/chromedriver
export GOOGLE_CHROME_OPTS_ARGS=headless,disable-gpu,no-sandbox,disable-dev-shm-usage
export REPORTING_DEMO_DATABASE=disposable REPORTING_DOC_SCREENSHOTS=/screenshots
bundle install
bundle exec rake db:migrate redmine:plugins:migrate
REDMINE_LANG=en bundle exec rake redmine:load_default_data
bundle exec ruby -Itest plugins/redmine_reporting/test/documentation/configuration_test.rb -v
' > "$results/run.log" 2>&1 || { echo "Documentation run failed: see $results/run.log" >&2; exit 1; }
mv "$results/screenshots/home.png" "$plugin_root/doc/images/redmine_reporting_home.png"
mkdir -p "$plugin_root/doc/screenshots/configuration"
cp "$results/screenshots/"*.png "$plugin_root/doc/screenshots/configuration/"
printf 'Screenshots copied to %s\n' "$plugin_root/doc/screenshots/configuration"
