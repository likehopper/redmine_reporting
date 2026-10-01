#!/usr/bin/env bash
# File: redmine_reporting/test/compatibility/run.sh
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
# Usage: bash test/compatibility/run.sh [5.0.14 5.1.13 6.0.11 6.1.4 7.0.1]
set -euo pipefail
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
results=$(mktemp -d "${TMPDIR:-/tmp}/redmine-reporting-compat.XXXXXX")
# All versions test one immutable snapshot even if the working tree changes.
mkdir "$results/plugin"
tar -C "$plugin_root" --exclude=.git --exclude=dist --exclude=.compat-sla -cf - . | tar -C "$results/plugin" -xf -
(cd "$results/plugin" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$results/source.sha256"
printf 'Logs and source snapshot: %s\n' "$results"
db="${COMPAT_DB:-sqlite}"
if [ "$#" = 0 ]; then
  if [ "$db" = sqlite ]; then set -- 5.0.14 5.1.13 6.0.11 6.1.4 7.0.1; else set -- 6.1.4; fi
fi
if [ "$db" != sqlite ] && [ "$#" != 1 ]; then
  echo "Select one Redmine version per external database run." >&2
  exit 2
fi
network=""
database_container=""
cleanup() {
  if [ -n "$database_container" ]; then docker rm -f "$database_container" >/dev/null 2>&1 || true; fi
  if [ -n "$network" ]; then docker network rm "$network" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
runtime_args=()
case "$db" in
  sqlite) ;;
  postgres|mariadb|mysql)
    network="reporting-test-$(basename "$results")"
    database_container="$network-db"
    docker network create "$network" > /dev/null
    case "$db" in
      postgres)
        docker run -d --name "$database_container" --network "$network" --network-alias db \
          -e POSTGRES_DB=redmine_test -e POSTGRES_USER=redmine -e POSTGRES_PASSWORD=reporting-test-only \
          --health-cmd='pg_isready -U redmine -d redmine_test' --health-interval=2s --health-retries=60 postgres:16 > /dev/null ;;
      mariadb)
        docker run -d --name "$database_container" --network "$network" --network-alias db \
          -e MARIADB_DATABASE=redmine_test -e MARIADB_USER=redmine -e MARIADB_PASSWORD=reporting-test-only -e MARIADB_ROOT_PASSWORD=reporting-root-test-only \
          --health-cmd='healthcheck.sh --connect --innodb_initialized' --health-interval=2s --health-retries=60 mariadb:10.11 > /dev/null ;;
      mysql)
        docker run -d --name "$database_container" --network "$network" --network-alias db \
          -e MYSQL_DATABASE=redmine_test -e MYSQL_USER=redmine -e MYSQL_PASSWORD=reporting-test-only -e MYSQL_ROOT_PASSWORD=reporting-root-test-only \
          --health-cmd='mysqladmin ping -h 127.0.0.1 -uredmine -preporting-test-only --silent' --health-interval=2s --health-retries=60 mysql:8.0 > /dev/null ;;
    esac
    ready=0
    for attempt in $(seq 1 90); do
      if [ "$(docker inspect -f '{{.State.Health.Status}}' "$database_container")" = healthy ]; then ready=1; break; fi
      sleep 2
    done
    [ "$ready" = 1 ] || { echo "Database startup failed" >&2; exit 1; }
    runtime_args+=(--network "$network")
    ;;
  *) echo "Unsupported database: $db" >&2; exit 2 ;;
esac
if [ -n "${COMPAT_SLA_PATH:-}" ]; then
  runtime_args+=(-v "$(cd "$COMPAT_SLA_PATH" && pwd):/sla:ro")
fi
mkdir -p "$results/artifacts"
failed=0
for version in "$@"; do
  case "$version" in
    5.0.14) base=redmine:5.0 ;;
    5.1.13) base=redmine:5.1 ;;
    6.0.11|6.1.4|7.0.1) base=redmine:$version ;;
    *) printf 'Unsupported matrix entry: %s\n' "$version" >&2; exit 2 ;;
  esac
  image="reporting-compat:$version"
  # Optional prebuilt test image; it must include test gems, Chromium and curl.
  if [ -n "${COMPAT_IMAGE_PREFIX:-}" ]; then
    image="$COMPAT_IMAGE_PREFIX:$version"
  elif ! docker build --build-arg "REDMINE_IMAGE=$base" -t "$image" \
      "$results/plugin/test/compatibility" > "$results/$version-build.log" 2>&1; then
    printf '%s BUILD FAILED\n' "$version" | tee -a "$results/results.txt"
    failed=1
    continue
  fi
  if docker run --rm --cpus=2 --memory=2g --entrypoint sh \
      -e "REDMINE_VERSION=$version" -e RAILS_ENV=test -e "COMPAT_DB=$db" -e "REPORTING_BENCHMARK=${REPORTING_BENCHMARK:-}" -e "REPORTING_DEMO_SMOKE=${REPORTING_DEMO_SMOKE:-}" "${runtime_args[@]}" \
      -v "$results/plugin:/plugin:ro" -v "$results/artifacts:/artifacts" "$image" \
      /plugin/test/compatibility/container.sh > "$results/$version.log" 2>&1; then
    printf '%s PASS\n' "$version" | tee -a "$results/results.txt"
  else
    printf '%s FAIL (see %s/%s.log)\n' "$version" "$results" "$version" | tee -a "$results/results.txt"
    failed=1
  fi
done
exit "$failed"
