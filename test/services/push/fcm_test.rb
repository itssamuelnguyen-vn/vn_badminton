require "test_helper"

# How Firebase's answers are read (Push::Fcm), without the network: the HTTP request is replaced.
class Push::FcmTest < ActiveSupport::TestCase
  setup do
    key = { type: "service_account", project_id: "vn-badminton-test", private_key: OpenSSL::PKey::RSA.new(2048).to_pem,
            client_email: "push@vn-badminton-test.iam.gserviceaccount.com", client_id: "1", token_uri: "https://oauth2.googleapis.com/token" }
    @fcm = Push::Fcm.new(key.to_json)
  end

  test "sends an Android notification with the page to open, to the project of the service account" do
    sent = answer(200, { name: "projects/vn-badminton-test/messages/1" })
    assert_equal :sent, @fcm.deliver(token: "fcm-1", title: "Sắp đến giờ chơi", body: "Sân 1 lúc 18:00", data: { path: "/bookings/K7Q2M9XA" })

    message = sent.last.fetch(:message)
    assert_equal [ "fcm-1", { title: "Sắp đến giờ chơi", body: "Sân 1 lúc 18:00" }, { path: "/bookings/K7Q2M9XA" } ],
                 message.values_at(:token, :notification, :data)
    assert_equal "updates", message.dig(:android, :notification, :channel_id)
  end

  test "tokens Firebase no longer knows are reported; outages raise to be retried; other refusals are logged" do
    answer(404, error("UNREGISTERED"))
    assert_equal :invalid_token, deliver
    answer(400, error("INVALID_ARGUMENT"))
    assert_equal :invalid_token, deliver
    answer(403, error("SENDER_ID_MISMATCH"))
    assert_equal :invalid_token, deliver

    [ 429, 500, 503, 401 ].each do |status|
      answer(status, error("UNAVAILABLE"))
      assert_raises(Push::Fcm::TransientError) { deliver }
    end

    answer(403, error("THIRD_PARTY_AUTH_ERROR"))
    assert_equal :failed, deliver
  end

  test "is off without a service account in the environment" do
    assert_nil Push::Fcm.from_env if ENV["FIREBASE_SERVICE_ACCOUNT_PATH"].blank? && ENV["FIREBASE_SERVICE_ACCOUNT_JSON"].blank?
    assert_not Push::Fcm::Disabled.new.enabled?
    assert_equal :skipped, Push::Fcm::Disabled.new.deliver(token: "x", title: "t", body: "b")
  end

  private

  def deliver = @fcm.deliver(token: "fcm-1", title: "t", body: "b")

  def error(code) = { error: { details: [ { "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: code } ] } }

  # The next requests are answered with status and body; returns the payloads sent.
  def answer(status, body)
    sent = []
    response = Net::HTTPResponse::CODE_TO_OBJ[status.to_s].new("1.1", status.to_s, "")
    response.instance_variable_set(:@body, body.to_json)
    response.instance_variable_set(:@read, true)
    @fcm.define_singleton_method(:post) do |payload|
      sent << payload.deep_symbolize_keys
      response
    end
    sent
  end
end
