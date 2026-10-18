require "test_helper"

class RateLimitTest < ActionDispatch::IntegrationTest
  test "too many sign-in attempts for one account are refused, even with the right password" do
    5.times { post user_session_path, params: { user: { login: "0901 234 567", password: "wrong" } } }

    post user_session_path, params: { user: { login: "0901234567", password: "password123" } }

    assert_redirected_to new_user_session_path
    assert_equal "Bạn thao tác quá nhiều lần. Vui lòng thử lại sau ít phút.", flash[:alert]
    assert_nil session["warden.user.user.key"]
  end

  test "too many sign-in attempts from one address are refused" do
    10.times { |i| post user_session_path, params: { user: { login: "guess#{i}@example.com", password: "wrong" } } }

    post user_session_path, params: { user: { login: "an@example.com", password: "password123" } }

    assert_redirected_to new_user_session_path
    assert_equal "Bạn thao tác quá nhiều lần. Vui lòng thử lại sau ít phút.", flash[:alert]
  end

  test "sign-ups are limited per address" do
    5.times { post user_registration_path, params: { user: { email: "" } } }

    assert_no_difference "User.count" do
      post user_registration_path, params: { user: { full_name: "Lê Cường", phone: "0987 654 321", email: "cuong@example.com",
                                                     password: "password123", password_confirmation: "password123" } }
    end
    assert_redirected_to new_user_registration_path
  end

  test "password reset emails are limited per email address" do
    assert_emails(3) { 3.times { post user_password_path, params: { user: { email: "an@example.com" } } } }

    assert_no_emails do
      assert_no_enqueued_emails do
        post user_password_path, params: { user: { email: " AN@example.com " } }
      end
    end
    assert_redirected_to new_user_password_path
    assert_equal "Bạn thao tác quá nhiều lần. Vui lòng thử lại sau ít phút.", flash[:alert]
  end
end
