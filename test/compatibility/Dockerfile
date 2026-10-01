# File: redmine_reporting/test/compatibility/Dockerfile
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
ARG REDMINE_IMAGE=redmine:6.1.4
FROM ${REDMINE_IMAGE}
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends chromium chromium-driver build-essential libsqlite3-dev curl \
 && rm -rf /var/lib/apt/lists/*
ENV BUNDLE_WITHOUT=development
RUN bundle config set without development
