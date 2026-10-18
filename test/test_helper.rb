ENV["RAILS_ENV"] ||= "test"
ENV["SEPAY_WEBHOOK_API_KEY"] ||= "test-sepay-key"
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

    # A bank transfer reported by SePay (POST /webhooks/sepay), by default paying the last payment exactly.
    def transfer(payment = Payment.last, amount: payment&.amount_vnd, content: "#{payment&.code} chuyen tien san", id: SecureRandom.random_number(10**9))
      post sepay_webhook_path, as: :json, headers: { "Authorization" => "Apikey #{ENV["SEPAY_WEBHOOK_API_KEY"]}" },
                               params: { id: id, gateway: "MBBank", transactionDate: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
                                         accountNumber: "0123456789", content: content, transferType: "in",
                                         transferAmount: amount, referenceCode: "FT#{id}" }
    end
  end
end
