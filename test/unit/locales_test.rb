# frozen_string_literal: true
# File: redmine_reporting/test/unit/locales_test.rb
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

require_relative "../test_helper"

class ReportingLocalesTest < ActiveSupport::TestCase
  LOCALES = File.expand_path("../../config/locales", __dir__)

  def test_french_and_english_define_the_same_keys
    keys = %w[fr en].to_h { |locale| [locale, flat_keys(YAML.load_file(File.join(LOCALES, "#{locale}.yml")).fetch(locale))] }
    assert_equal keys["en"], keys["fr"]
  end

  def test_placeholders_match_between_languages
    french, english = %w[fr en].map { |locale| YAML.load_file(File.join(LOCALES, "#{locale}.yml")).fetch(locale) }
    flat_keys(french).each do |key|
      placeholders = [french, english].map { |tree| tree.dig(*key.split(".")).to_s.scan(/%\{\w+\}/).sort }
      assert_equal placeholders.first, placeholders.last, key
    end
  end

  private

  def flat_keys(tree, prefix = nil)
    tree.flat_map do |key, value|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? flat_keys(value, path) : [path]
    end.sort
  end
end
