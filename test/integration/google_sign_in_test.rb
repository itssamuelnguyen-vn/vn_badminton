require "test_helper"

# "Sign in with Google" on the web (AP-05), with Google's check of the ID token faked; the app's is in
# test/integration/api/google_sign_in_test.rb.
class GoogleSignInTest < ActionDispatch::IntegrationTest
  include GoogleTestHelpers
  include ActionMailer::TestHelper

  test "the sign-in and sign-up pages have Google's button, posting to the server with the web client ID" do
    get new_user_session_path
    assert_select "form[action='/users/google'][hidden][data-controller='google-sign-in']" \
                  "[data-google-sign-in-client-id-value='#{Accounts::GoogleIdentity::DEFAULT_CLIENT_ID}'] input[name=credential]"
    get new_user_registration_path
    assert_select "form[action='/users/google']"
  end

  test "an account with the Google email signs in, is linked and its email confirmed" do
    users(:an).update_columns(confirmed_at: nil)
    post google_sign_in_path, params: { credential: "good:g-123:AN@example.com" }
    assert_redirected_to root_path
    follow_redirect!
    assert_select "form[action='/users/sign_out']"
    users(:an).reload.then { |an| assert_equal [ "g-123", true ], [ an.google_uid, an.confirmed? ] }

    # Another Google account with the same email is refused.
    delete destroy_user_session_path
    post google_sign_in_path, params: { credential: "good:g-999:an@example.com" }
    assert_redirected_to new_user_session_path
    assert_equal "Không đăng nhập được bằng Google. Vui lòng thử lại.", flash[:alert]
  end

  test "refuses forged and unverified tokens; says when Google cannot be reached" do
    %w[forged unverified:g-1:x@example.com].each do |credential|
      post google_sign_in_path, params: { credential: credential }
      assert_redirected_to new_user_session_path
      assert_equal "Không đăng nhập được bằng Google. Vui lòng thử lại.", flash[:alert]
    end
    post google_sign_in_path, params: { credential: "offline" }
    assert_equal "Chưa kết nối được Google, vui lòng thử lại sau ít phút.", flash[:alert]
  end

  test "someone new gives a phone number and consent to finish: verified email, no verification email, signed in" do
    post google_sign_in_path, params: { credential: "good:g-new:binh@example.com" }
    assert_redirected_to new_google_sign_in_path
    follow_redirect!
    assert_select "p", text: /binh@example.com/
    assert_select "input[name='user[full_name]'][value='Trần Bình']"

    post register_google_sign_in_path, params: { user: { full_name: "Trần Bình", phone: "", privacy_consent: "1" } }
    assert_response :unprocessable_content
    assert_nil User.find_by(email: "binh@example.com")

    assert_no_emails do
      post register_google_sign_in_path, params: { user: { full_name: "Trần Bình", phone: "0912 345 678", privacy_consent: "1" } }
    end
    assert_redirected_to root_path
    user = User.find_by!(email: "binh@example.com")
    assert_equal [ "g-new", true, "+84912345678", "vi" ], [ user.google_uid, user.confirmed?, user.phone, user.locale ]

    # The signup is over: the page sends back to sign in.
    get new_google_sign_in_path
    assert_redirected_to new_user_session_path
  end

  test "the signup expires" do
    post google_sign_in_path, params: { credential: "good:g-new:binh@example.com" }
    travel Accounts::GoogleIdentity::SIGNUP_TTL + 1.minute
    post register_google_sign_in_path, params: { user: { full_name: "Trần Bình", phone: "0912 345 678", privacy_consent: "1" } }
    assert_redirected_to new_user_session_path
    assert_equal "Đã quá thời gian đăng ký, vui lòng đăng nhập bằng Google lại.", flash[:alert]
    assert_nil User.find_by(email: "binh@example.com")
  end
end
