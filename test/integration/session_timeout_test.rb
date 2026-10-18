require "test_helper"

# Everyone signs in again after 30 minutes without activity (Devise :timeoutable, no "remember me").
class SessionTimeoutTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "the owner is signed out after 30 minutes without activity" do
    sign_in_with_form "owner@example.com"
    get admin_root_path
    assert_response :success

    travel 31.minutes
    get admin_root_path
    assert_signed_out_by_timeout

    get admin_root_path
    assert_redirected_to new_user_session_path, "still signed out"
  end

  test "each request restarts the 30 minutes" do
    sign_in_with_form "an@example.com"

    3.times do
      travel 25.minutes
      get bookings_path
      assert_response :success
    end
  end

  test "live schedule refreshes do not keep the session alive" do
    sign_in_with_form "an@example.com"

    travel 20.minutes
    get root_path, headers: { "X-Background-Refresh" => "1" }
    assert_response :success
    travel 11.minutes # 31 minutes since the last real request
    get bookings_path
    assert_signed_out_by_timeout
  end

  test "signed-in pages reload themselves when the session expires; there is no remember me" do
    get new_user_session_path
    assert_select "input[name='user[remember_me]']", count: 0
    assert_select "body[data-controller]", count: 0

    sign_in_with_form "an@example.com"
    get root_path
    assert_select "body[data-controller='session-timeout'][data-session-timeout-seconds-value='1800']"
  end

  private

  # Devise sends a timed-out request back to the same page, which then asks to sign in, with the timeout message.
  def assert_signed_out_by_timeout
    follow_redirect! while response.redirect? && !response.location.end_with?("/users/sign_in")
    assert_redirected_to new_user_session_path
    follow_redirect!
    assert_select "[role=alert]", text: "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại để tiếp tục."
  end

  def sign_in_with_form(login)
    post user_session_path, params: { user: { login: login, password: "password123" } }
    assert_response :redirect
  end
end
