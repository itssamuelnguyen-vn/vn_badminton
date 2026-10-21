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
    # Push notifications are off unless a test turns them on with a fake Firebase (FakeFcm), whatever the
    # environment says.
    setup { Push::Fcm.current = Push::Fcm::Disabled.new }
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers

    # Like ApplicationController#default_url_options: with a :locale key present, positional
    # route arguments (booking_path(booking)) fill :code instead of the optional (:locale) segment.
    setup { default_url_options[:locale] = nil }

    # No page may show untranslated or unpluralized text ("{other: ...}", "%{count}", "translation missing"):
    # every HTML response of every integration test is checked.
    %i[get post patch put delete].each do |verb|
      define_method(verb) do |*args, **options|
        super(*args, **options).tap do
          # Pages people see: successful ones and re-rendered forms (error pages in tests show Rails' debug page).
          next unless response.media_type == "text/html" && (response.successful? || response.unprocessable?)

          # data-*-value attributes carry templates for JavaScript on purpose (e.g. "%{amount}đ" for the slot picker).
          visible = response.body.gsub(/data-[\w-]+-value="[^"]*"/, "")
          leak = visible[/\{:?(?:zero|one|other):|%\{\w+\}|translation[ _]missing/i]
          flunk "Translation problem #{leak.inspect} on #{request.method} #{request.path}" if leak
        end
      end
    end

    # A bank transfer reported by SePay (POST /webhooks/sepay), by default paying the last payment exactly.
    def transfer(payment = Payment.last, amount: payment&.amount_vnd, content: "#{payment&.code} chuyen tien san", id: SecureRandom.random_number(10**9))
      post sepay_webhook_path, as: :json, headers: { "Authorization" => "Apikey #{ENV["SEPAY_WEBHOOK_API_KEY"]}" },
                               params: { id: id, gateway: "MBBank", transactionDate: Time.current.strftime("%Y-%m-%d %H:%M:%S"),
                                         accountNumber: "0123456789", content: content, transferType: "in",
                                         transferAmount: amount, referenceCode: "FT#{id}" }
    end
  end
end

# Signing in to the mobile app's API (Api::V1) in integration tests.
module ApiTestHelpers
  private

  def sign_in_api(user)
    post api_v1_session_path, params: { login: user.email, password: "password123", device_name: "Pixel" }, as: :json
    assert_response :created
    response.parsed_body["token"]
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }
end

# Firebase Cloud Messaging in the tests (Push::Fcm.current = FakeFcm.new): keeps what would be sent, and answers
# :invalid_token for the tokens in invalid_tokens.
class FakeFcm
  attr_reader :sent, :invalid_tokens

  def initialize
    @sent = []
    @invalid_tokens = []
  end

  def enabled? = true

  def deliver(token:, title:, body:, data: {})
    @sent << { token: token, title: title, body: body, data: data }
    invalid_tokens.include?(token) ? :invalid_token : :sent
  end
end
