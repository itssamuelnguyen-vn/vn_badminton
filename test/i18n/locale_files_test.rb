require "test_helper"

# Every key in an English locale file must exist in its Vietnamese counterpart and vice versa.
class LocaleFilesTest < ActiveSupport::TestCase
  PAIRS = { "en.yml" => "vi.yml", "devise.en.yml" => "devise.vi.yml" }.freeze
  # Pluralization keys differ by language (Vietnamese only has "other").
  PLURAL_KEYS = %w[zero one two few many].freeze

  PAIRS.each do |en_file, vi_file|
    test "#{vi_file} has the same keys as #{en_file}" do
      en_keys = keys_of(en_file, "en")
      vi_keys = keys_of(vi_file, "vi")

      assert_empty en_keys - vi_keys, "missing from #{vi_file}"
      assert_empty vi_keys - en_keys, "missing from #{en_file}"
    end
  end

  private

  def keys_of(file, locale)
    flatten(YAML.load_file(Rails.root.join("config/locales", file)).fetch(locale)).to_set
  end

  def flatten(hash, prefix = nil)
    hash.flat_map do |key, value|
      next [] if PLURAL_KEYS.include?(key)

      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flatten(value, path) : [ path ]
    end
  end
end
