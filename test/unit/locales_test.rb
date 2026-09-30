# frozen_string_literal: true

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
