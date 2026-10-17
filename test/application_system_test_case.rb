require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # CHROME_BIN points at a Chrome that is not on the PATH (e.g. one downloaded by Selenium Manager).
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
  end

  # Let click_on & co. find icon-only buttons and links by their aria-label.
  Capybara.enable_aria_label = true

  # Same reason as in ActionDispatch::IntegrationTest (test_helper.rb).
  setup { default_url_options[:locale] = nil }
end
