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
# The image is disposable; no existing database or writable host mount is used.
rm -rf plugins/redmine_sla plugins/redmine_reporting
cp -a /plugin plugins/redmine_reporting
cat > config/database.yml <<'YAML'
test:
  adapter: sqlite3
  database: db/reporting_compat.sqlite3
YAML
export RAILS_ENV=test
export CHROMEDRIVER_PATH=/usr/bin/chromedriver
export GOOGLE_CHROME_OPTS_ARGS=headless,disable-gpu,no-sandbox,disable-dev-shm-usage
bundle install
bundle exec rake db:migrate redmine:plugins:migrate
bundle exec rails runner 'abort "Wrong Redmine version" unless Redmine::VERSION.to_a.first(3).join(".") == ENV.fetch("REDMINE_VERSION"); puts "Redmine #{Redmine::VERSION} / Ruby #{RUBY_VERSION} / Rails #{Rails.version}"'
# Verify uninstall/reinstall before fixtures reset Redmine's plugin migration registry.
bundle exec rake redmine:plugins:migrate NAME=redmine_reporting VERSION=0
bundle exec rake redmine:plugins:migrate NAME=redmine_reporting
bundle exec rake redmine:plugins:test NAME=redmine_reporting
