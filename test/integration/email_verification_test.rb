require "test_helper"

class EmailVerificationTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.parse("2026-10-19 10:00") }

  test "a new account can sign in but must verify its email before booking" do
    perform_enqueued_jobs do
      post user_registration_path(locale: :en), params: { user: {
        full_name: "Lê Cường", phone: "0987 654 321", email: "cuong@example.com",
        password: "password123", password_confirmation: "password123", privacy_consent: "1", locale: "en"
      } }
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "cuong@example.com" ], mail.to
    assert_equal "Verify your VN Badminton email", mail.subject
    assert_includes mail.body.to_s, "The link is valid for 3 days."
    assert_no_match(/%\{|\{:?(one|other)/, mail.body.to_s, "no untranslated or unpluralized text")
    link = mail.body.to_s[%r{http://example.com/en/users/confirmation\?confirmation_token=[^"]+}]
    assert link

    get root_path
    assert_select "header + [role=status]", text: /email xác minh đã gửi tới cuong@example.com/
    get new_booking_path(slots: { "0" => slot("18:00", "19:00") })
    assert_redirected_to root_path
    assert_equal "Vui lòng xác minh email trước khi đặt sân. Chúng tôi đã gửi đường dẫn xác minh tới email của bạn.", flash[:alert]

    get URI(link).request_uri # the session cookie belongs to www.example.com, the test host
    assert_redirected_to root_path(locale: :en) # the link keeps the language of the email
    assert User.find_by!(email: "cuong@example.com").confirmed?

    get new_booking_path(slots: { "0" => slot("18:00", "19:00") })
    assert_response :success
    assert_select "header + [role=status]", count: 0
  end

  test "the verification email can be sent again" do
    user = User.create!(email: "cuong@example.com", full_name: "Lê Cường", phone: "0987 654 321", password: "password123")
    sign_in user

    assert_enqueued_email_with Devise::Mailer, :confirmation_instructions, args: ->(args) { args.first == user } do
      post user_confirmation_path, params: { user: { email: user.email } }
    end
  end

  test "a new email address is only used once verified" do
    sign_in users(:an)

    assert_enqueued_emails 1 do
      put user_registration_path, params: { user: { email: "an.moi@example.com", current_password: "password123" } }
    end

    user = users(:an).reload
    assert_equal "an@example.com", user.email
    assert_equal "an.moi@example.com", user.unconfirmed_email
    assert user.confirmed?, "the account itself stays verified"
    get edit_user_registration_path
    assert_select ".form-hint", text: /Đang chờ xác minh email mới: an.moi@example.com/
  end

  test "the verification email in Vietnamese" do
    user = User.new(email: "cuong@example.com", full_name: "Lê Cường", phone: "0987 654 321", password: "password123")
    user.skip_confirmation_notification!
    user.save!

    mail = Devise::Mailer.confirmation_instructions(user, "token")

    assert_equal "Xác minh email tài khoản VN Badminton", mail.subject
    assert_includes mail.body.to_s, "Xin chào Lê Cường,"
    assert_includes mail.body.to_s, "Đường dẫn có hiệu lực trong 3 ngày."
    assert_no_match(/%\{|\{:?(one|other)/, mail.body.to_s)
  end

  private

  def slot(from, to)
    { court_id: courts(:court_one).id, starts_at: Time.zone.parse("2026-10-20 #{from}").iso8601, ends_at: Time.zone.parse("2026-10-20 #{to}").iso8601 }
  end
end
