#!/bin/sh
# Only run inside the disposable compatibility container.
set -eu
case "$REDMINE_VERSION" in
  5.0.14|5.1.13)
    # These exact tags are unavailable on Docker Hub. Keep a supported Ruby
    # from the branch image, but test the checksum-verified official source.
    cd /tmp
    archive="redmine-$REDMINE_VERSION.tar.gz"
    curl -fsSLO "https://www.redmine.org/releases/$archive"
    curl -fsSLO "https://www.redmine.org/releases/$archive.sha256"
    sha256sum -c "$archive.sha256"
    tar xzf "$archive"
    cd "redmine-$REDMINE_VERSION"
    ;;
esac
# The image is disposable; only the screenshot artifact directory is writable on the host.
rm -rf plugins/redmine_sla plugins/redmine_reporting
cp -a /plugin plugins/redmine_reporting
if [ -d /sla ]; then cp -a /sla plugins/redmine_sla; fi
if [ "${COMPAT_DB:-sqlite}" = sqlite ]; then
  cat > config/database.yml <<'YAML'
test:
  adapter: sqlite3
  database: db/reporting_compat.sqlite3
YAML
else
  case "$COMPAT_DB" in
    postgres) adapter=postgresql ;;
    mariadb|mysql) adapter=mysql2 ;;
    *) exit 2 ;;
  esac
  cat > config/database.yml <<YAML
test:
  adapter: $adapter
  host: db
  database: redmine_test
  username: redmine
  password: reporting-test-only
  encoding: utf8
YAML
  if [ "$adapter" = mysql2 ]; then
    cat >> config/database.yml <<'YAML'
  variables:
    sql_mode: STRICT_ALL_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION
YAML
  fi
fi
# Schema loading avoids requiring host-specific pg_dump/mysqldump executables.
cat > config/initializers/reporting_test_schema.rb <<'RUBY'
Rails.application.config.active_record.schema_format = :ruby
RUBY
export RAILS_ENV=test
export CHROMEDRIVER_PATH=/usr/bin/chromedriver
export GOOGLE_CHROME_OPTS_ARGS=headless,disable-gpu,no-sandbox,disable-dev-shm-usage
bundle install
bundle exec rake db:migrate redmine:plugins:migrate
bundle exec rails runner 'abort "Wrong Redmine version" unless Redmine::VERSION.to_a.first(3).join(".") == ENV.fetch("REDMINE_VERSION"); puts "Redmine #{Redmine::VERSION} / Ruby #{RUBY_VERSION} / Rails #{Rails.version}"'
# Verify uninstall/reinstall before fixtures reset Redmine's plugin migration registry.
bundle exec rake redmine:plugins:migrate NAME=redmine_reporting VERSION=0
bundle exec rake redmine:plugins:migrate NAME=redmine_reporting
if [ "${REPORTING_DEMO_SMOKE:-}" = 1 ]; then
  REDMINE_LANG=en bundle exec rake redmine:load_default_data
  REPORTING_DEMO_DATABASE=disposable bundle exec rails runner plugins/redmine_reporting/test/compatibility/demo_smoke.rb
else
  bundle exec rake redmine:plugins:test NAME=redmine_reporting
fi
if [ -n "${REPORTING_BENCHMARK:-}" ]; then bundle exec ruby -Itest plugins/redmine_reporting/test/compatibility/benchmark.rb; fi
