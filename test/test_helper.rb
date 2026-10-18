ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate limit counts would otherwise carry over from one test to the next.
    setup { ApplicationController::RATE_LIMIT_STORE.clear }
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers

    # Like ApplicationController#default_url_options: with a :locale key present, positional
    # route arguments (booking_path(booking)) fill :code instead of the optional (:locale) segment.
    setup { default_url_options[:locale] = nil }
  end
end
