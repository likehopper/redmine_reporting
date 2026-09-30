#!/usr/bin/env bash
# Usage: bash test/compatibility/run.sh [5.0.14 5.1.13 6.0.11 6.1.4 7.0.1]
set -euo pipefail
plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
results=$(mktemp -d "${TMPDIR:-/tmp}/redmine-reporting-compat.XXXXXX")
# All versions test one immutable snapshot even if the working tree changes.
cp -a "$plugin_root" "$results/plugin"
(cd "$results/plugin" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$results/source.sha256"
printf 'Logs and source snapshot: %s\n' "$results"
if [ "$#" = 0 ]; then set -- 5.0.14 5.1.13 6.0.11 6.1.4 7.0.1; fi
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
      -e "REDMINE_VERSION=$version" -e RAILS_ENV=test \
      -v "$results/plugin:/plugin:ro" "$image" \
      /plugin/test/compatibility/container.sh > "$results/$version.log" 2>&1; then
    printf '%s PASS\n' "$version" | tee -a "$results/results.txt"
  else
    printf '%s FAIL (see %s/%s.log)\n' "$version" "$results" "$version" | tee -a "$results/results.txt"
    failed=1
  fi
done
exit "$failed"
