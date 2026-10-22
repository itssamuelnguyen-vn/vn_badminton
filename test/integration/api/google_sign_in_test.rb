require "test_helper"

# "Sign in with Google" in the app (Accounts::GoogleIdentity), with Google's check of the ID token faked.
class Api::GoogleSignInTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers
  include ActionMailer::TestHelper

  # Fake ID tokens: "good:<sub>:<email>" is valid for the web client ID; anything else is refused as Google would.
  FAKE_VERIFIER = lambda do |id_token, client_ids|
    raise Google::Auth::IDTokens::KeySourceError, "offline" if id_token == "offline"

    kind, sub, email = id_token.split(":")
    raise Google::Auth::IDTokens::AudienceMismatchError, "aud" unless client_ids.include?(Accounts::GoogleIdentity::DEFAULT_CLIENT_ID)
    raise Google::Auth::IDTokens::SignatureError, "forged" unless %w[good unverified].include?(kind)

    { "sub" => sub, "email" => email, "email_verified" => kind == "good", "name" => "  Trần   Bình " }
  end

  setup do
    @original_verifier = Accounts::GoogleIdentity.verifier
    Accounts::GoogleIdentity.verifier = FAKE_VERIFIER
  end

  teardown { Accounts::GoogleIdentity.verifier = @original_verifier }

  test "an account with the Google email signs in and is linked; later by its Google ID even if the email changed" do
    users(:an).update_columns(confirmed_at: nil)
    post google_api_v1_session_path, params: { id_token: "good:g-123:AN@example.com", device_name: "Pixel" }, as: :json
    assert_response :created
    assert_equal "Nguyễn An", response.parsed_body.dig("user", "full_name")
    assert_equal [ "g-123", true ], [ users(:an).reload.google_uid, users(:an).confirmed? ]
    get api_v1_account_path, headers: auth(response.parsed_body["token"])
    assert_response :success

    users(:an).update_columns(email: "an.new@example.com")
    post google_api_v1_session_path, params: { id_token: "good:g-123:an@example.com" }, as: :json
    assert_response :created
    assert_equal "an.new@example.com", response.parsed_body.dig("user", "email")

    # The email's account is linked to another Google account.
    post google_api_v1_session_path, params: { id_token: "good:g-other:an.new@example.com" }, as: :json
    assert_response :unauthorized
    assert_equal "invalid_google", response.parsed_body["error"]
  end

  test "refuses forged and unverified tokens, and accounts being deleted; says when Google cannot be reached" do
    post google_api_v1_session_path, params: { id_token: "forged:g-1:an@example.com" }, as: :json
    assert_response :unauthorized
    assert_equal [ "Không đăng nhập được bằng Google. Vui lòng thử lại." ], response.parsed_body["messages"]

    post google_api_v1_session_path, params: { id_token: "unverified:g-1:an@example.com" }, as: :json
    assert_response :unauthorized
    assert_nil users(:an).reload.google_uid

    post google_api_v1_session_path, params: { id_token: "" }, as: :json
    assert_response :unauthorized

    ENV["GOOGLE_WEB_CLIENT_ID"] = "another-app.apps.googleusercontent.com"
    post google_api_v1_session_path, params: { id_token: "good:g-1:an@example.com" }, as: :json
    assert_response :unauthorized
    ENV.delete("GOOGLE_WEB_CLIENT_ID")

    post google_api_v1_session_path, params: { id_token: "offline" }, headers: { "Accept-Language" => "en" }, as: :json
    assert_response :service_unavailable
    assert_equal "google_unavailable", response.parsed_body["error"]

    users(:an).update_columns(deletion_requested_at: Time.current)
    post google_api_v1_session_path, params: { id_token: "good:g-1:an@example.com" }, as: :json
    assert_response :forbidden
    assert_equal "account_deleted", response.parsed_body["error"]
  ensure
    ENV.delete("GOOGLE_WEB_CLIENT_ID")
  end

  test "someone new gives a phone number to finish: verified email, no verification email, signed in" do
    post google_api_v1_session_path, params: { id_token: "good:g-new:binh@gmail.com" }, as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal [ true, "Trần Bình", "binh@gmail.com" ], body.values_at("needs_phone", "name", "email")
    assert_not User.exists?(email: "binh@gmail.com")

    signup = { signup_token: body["signup_token"], full_name: "Trần Bình", phone: "0901 234 567", privacy_consent: true, locale: "en" }
    post google_api_v1_registration_path, params: signup, as: :json
    assert_response :unprocessable_content
    assert_includes response.parsed_body["messages"].join, "Số điện thoại"

    post google_api_v1_registration_path, params: signup.merge(phone: "0912 000 333", privacy_consent: false), as: :json
    assert_response :unprocessable_content

    assert_no_enqueued_emails do
      post google_api_v1_registration_path, params: signup.merge(phone: "0912 000 333", device_name: "Pixel"), as: :json
    end
    assert_response :created
    user = User.find_by!(email: "binh@gmail.com")
    assert_equal [ "g-new", "+84912000333", "en", true ], [ user.google_uid, user.phone, user.locale, user.confirmed? ]
    assert user.privacy_accepted_at
    assert_equal user.id, response.parsed_body.dig("user", "id")

    post google_api_v1_session_path, params: { id_token: "good:g-new:binh@gmail.com" }, as: :json
    assert_response :created
  end

  test "the signup token cannot be forged nor used late" do
    post google_api_v1_session_path, params: { id_token: "good:g-new:binh@gmail.com" }, as: :json
    signup_token = response.parsed_body["signup_token"]

    post google_api_v1_registration_path, params: { signup_token: "#{signup_token}x", phone: "0912 000 333", privacy_consent: true }, as: :json
    assert_response :unprocessable_content
    assert_equal "signup_expired", response.parsed_body["error"]

    travel Accounts::GoogleIdentity::SIGNUP_TTL + 1.minute do
      post google_api_v1_registration_path, params: { signup_token: signup_token, phone: "0912 000 333", privacy_consent: true }, as: :json
    end
    assert_equal "signup_expired", response.parsed_body["error"]
    assert_not User.exists?(email: "binh@gmail.com")
  end

  test "Google sign-in is rate limited like the password sign-in" do
    10.times { post google_api_v1_session_path, params: { id_token: "forged" }, as: :json }
    post google_api_v1_session_path, params: { id_token: "good:g-1:an@example.com" }, as: :json
    assert_response :too_many_requests
  end
end
