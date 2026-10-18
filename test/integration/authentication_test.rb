require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "signs up with name, phone, email and password" do
    assert_difference "User.count", 1 do
      post user_registration_path, params: { user: {
        full_name: "Lê Cường", phone: "0987 654 321", email: "cuong@example.com",
        password: "password123", password_confirmation: "password123", privacy_consent: "1"
      } }
    end

    user = User.find_by!(email: "cuong@example.com")
    assert_equal "+84987654321", user.phone
    assert user.customer?
    assert_redirected_to root_path
    follow_redirect!
    assert_select "main [role=status]", "Chào mừng! Bạn đã đăng ký thành công. Vui lòng mở email xác minh chúng tôi vừa gửi để có thể đặt sân."
  end

  test "sign-up requires agreeing to the privacy policy and records when" do
    travel_to Time.zone.parse("2026-10-19 10:00")
    params = { full_name: "Lê Cường", phone: "0987 654 321", email: "cuong@example.com",
               password: "password123", password_confirmation: "password123" }

    get new_user_registration_path
    assert_select "input[type=checkbox][name='user[privacy_consent]'][required]"
    assert_select "label a[href='/privacy']", text: "chính sách bảo mật"

    assert_no_difference("User.count") { post user_registration_path, params: { user: params.merge(privacy_consent: "0") } }
    assert_select "#error_explanation li", text: "Bạn cần đồng ý với chính sách bảo mật để đăng ký"

    post user_registration_path, params: { user: params.merge(privacy_consent: "1") }
    assert_equal Time.current, User.find_by!(email: "cuong@example.com").privacy_accepted_at
  end

  test "the privacy policy is public, in both languages" do
    get privacy_path
    assert_select "h1", "Chính sách bảo mật"
    assert_select "footer a[href='/privacy']"

    get privacy_path(locale: :en)
    assert_select "h1", "Privacy policy"
  end

  test "remembers the language used to sign up" do
    get new_user_registration_path(locale: :en)
    assert_select "input[type=hidden][name='user[locale]'][value=en]"

    post user_registration_path(locale: :en), params: { user: {
      full_name: "Lê Cường", phone: "0987 654 321", email: "cuong@example.com",
      password: "password123", password_confirmation: "password123", locale: "en", privacy_consent: "1"
    } }

    assert_equal "en", User.find_by!(email: "cuong@example.com").locale
  end

  test "sign-up cannot choose its own role" do
    post user_registration_path, params: { user: {
      full_name: "Hacker", phone: "0987654321", email: "hacker@example.com",
      password: "password123", password_confirmation: "password123", role: "admin", privacy_consent: "1"
    } }

    assert User.find_by!(email: "hacker@example.com").customer?
  end

  test "shows translated errors when sign-up fails" do
    assert_no_difference "User.count" do
      post user_registration_path, params: { user: {
        full_name: "", phone: "123", email: "an@example.com", password: "short", password_confirmation: "other"
      } }
    end

    assert_response :unprocessable_content
    assert_select "#error_explanation li", text: "Email đã tồn tại"
    assert_select "#error_explanation li", text: "Mật khẩu quá ngắn (tối thiểu 8 ký tự)"
    assert_select "#error_explanation li", text: "Xác nhận mật khẩu không khớp với mật khẩu"
    assert_select "#error_explanation p", text: "Vui lòng kiểm tra lại 5 lỗi bên dưới:"
    assert_select "input#user_password[aria-invalid=true]"
  end

  test "signs in with email" do
    sign_in_with "an@example.com", "password123"

    assert_redirected_to root_path
    follow_redirect!
    assert_select "header", text: /Nguyễn An/
  end

  test "signs in with phone number in a local format" do
    sign_in_with "0901 234 567", "password123"

    assert_redirected_to root_path
  end

  test "rejects a wrong password without revealing whether the account exists" do
    sign_in_with "an@example.com", "wrong-password"
    assert_response :unprocessable_content
    assert_select "[role=alert]", "Email/số điện thoại hoặc mật khẩu không đúng."

    sign_in_with "0999999999", "password123"
    assert_select "[role=alert]", "Email/số điện thoại hoặc mật khẩu không đúng."
  end

  test "signs out" do
    sign_in users(:an)

    delete destroy_user_session_path

    assert_redirected_to root_path
    follow_redirect!
    assert_select "header a", text: "Đăng nhập"
  end

  test "account settings require sign-in" do
    get edit_user_registration_path

    assert_redirected_to new_user_session_path
  end

  test "account settings show the phone number in local format" do
    sign_in users(:an)

    get edit_user_registration_path

    assert_select "input#user_phone[value='0901 234 567']"
  end

  test "updates the account with the current password" do
    sign_in users(:an)

    put user_registration_path, params: { user: { full_name: "Nguyễn Văn An", phone: "0911 111 111", current_password: "password123" } }

    assert_redirected_to root_path
    assert_equal "Nguyễn Văn An", users(:an).reload.full_name
    assert_equal "+84911111111", users(:an).phone
  end

  test "sends a password reset email in the current locale and resets the password" do
    assert_emails 1 do
      post user_password_path(locale: :en), params: { user: { email: "an@example.com" } }
    end

    mail = ActionMailer::Base.deliveries.last
    assert_equal "Reset password instructions", mail.subject
    link = mail.body.to_s[%r{http://example\.com(/en/users/password/edit\?reset_password_token=[^"]+)}, 1]
    assert link, "reset link with the /en prefix"

    get link
    token = css_select("input[name='user[reset_password_token]']").first["value"]
    put user_password_path(locale: :en), params: { user: {
      reset_password_token: token, password: "new-password1", password_confirmation: "new-password1"
    } }

    assert users(:an).reload.valid_password?("new-password1")
  end

  test "password reset does not reveal unknown emails" do
    assert_no_emails do
      post user_password_path, params: { user: { email: "nobody@example.com" } }
    end

    assert_redirected_to new_user_session_path
  end

  private

  def sign_in_with(login, password)
    post user_session_path, params: { user: { login: login, password: password } }
  end
end
