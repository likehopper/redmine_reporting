ARG REDMINE_IMAGE=redmine:6.1.4
FROM ${REDMINE_IMAGE}
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium chromium-driver build-essential libsqlite3-dev curl \
 && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_WITHOUT=development
RUN bundle config set without development
