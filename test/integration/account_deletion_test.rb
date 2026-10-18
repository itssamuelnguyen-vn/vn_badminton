require "test_helper"

# Customers delete their own account, the owner deletes customers' and staff accounts (Accounts::Deletion):
# locked and signed out at once, personal data removed once nothing is left to play.
class AccountDeletionTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @slots = { "0" => { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } }
  end

  test "a customer with nothing booked deletes their account at once, with their password" do
    user = users(:an)
    sign_in user

    delete user_registration_path, params: { user: { current_password: "wrong" } }
    assert_equal "Mật khẩu không đúng.", flash[:alert]
    assert_nil user.reload.deletion_requested_at

    assert_enqueued_email_with AccountMailer, :deleted, params: { email: "an@example.com", name: "Nguyễn An", locale: "vi" } do
      delete user_registration_path, params: { user: { current_password: "password123" } }
    end
    assert_redirected_to root_path
    assert_equal "Tài khoản của bạn đã được xoá. Chúng tôi đã gửi email xác nhận.", flash[:notice]

    user.reload
    assert user.deleted_at
    assert_equal [ Accounts::Deletion::ANONYMOUS_NAME, "deleted-#{user.id}@deleted.invalid", nil ], [ user.full_name, user.email, user.phone ]

    post user_session_path, params: { user: { login: "an@example.com", password: "password123" } }
    assert_nil session["warden.user.user.key"]
  end

  test "with a booking still to play, the account is locked at once and deleted after the booking" do
    user = users(:an)
    sign_in user
    post bookings_path, params: { booking: { slots: @slots } }
    booking = Booking.last
    CustomerProfile.create!(phone: user.phone, note: "Hay đến sớm")

    other_device = open_session
    other_device.sign_in user
    other_device.get bookings_path
    assert_equal 200, other_device.response.status

    get edit_user_registration_path
    assert_select "[role=alert]", text: /Bạn còn 1 lượt chưa chơi.*Sân 1 · 20\/10\/2026 18:00 – 19:30/m

    assert_broadcasts Turbo::StreamsChannel.send(:stream_name_from, [ user, :account ]), 1 do # open pages reload
      assert_enqueued_email_with AccountMailer, :deletion_requested, params: ->(params) { params[:bookings].map { |b| b[:code] } == [ booking.code ] } do
        delete user_registration_path, params: { user: { current_password: "password123" } }
      end
    end
    assert_match "sẽ bị xoá sau khi lượt chơi cuối kết thúc", flash[:notice]
    assert user.reload.deletion_requested_at
    assert_nil user.deleted_at

    other_device.get bookings_path
    assert_equal 302, other_device.response.status, "signed out on every device"
    post user_session_path, params: { user: { login: "an@example.com", password: "password123" } }
    assert_nil session["warden.user.user.key"]

    get payment_path(booking.payment)
    assert_response :success, "the payment page still shows the QR code"
    assert_enqueued_email_with BookingMailer, :confirmed, params: ->(params) { params[:bookings] == [ booking ] } do
      transfer(booking.payment)
    end
    assert booking.reload.confirmed?, "a transfer arriving meanwhile still confirms the booking"

    AccountDeletionJob.perform_now
    assert_nil user.reload.deleted_at, "not before the booking is played"

    travel_to at("19:31")
    assert_enqueued_email_with AccountMailer, :deleted, params: { email: "an@example.com", name: "Nguyễn An", locale: "vi" } do
      AccountDeletionJob.perform_now
    end
    assert user.reload.deleted_at
    booking.reload
    assert_equal [ Accounts::Deletion::ANONYMOUS_NAME, nil ], [ booking.customer_name, booking.customer_phone ]
    assert_equal 180_000, booking.total_amount_vnd, "the records stay"
    assert_nil CustomerProfile.find_by(phone: "+84901234567"), "the private note goes"

    sign_in users(:owner)
    get admin_booking_path(booking)
    assert_select "li", text: /Khách đã xoá tài khoản/
    get admin_customers_path
    assert_response :success
    get admin_root_path(date: "2026-10-20")
    assert_select "p", text: /Khách đã xoá tài khoản · 180.000đ/

    booking.cancel_for_venue_fault!(by: users(:owner), now: at("21:00"))
    booking.mark_refunded!(by: users(:owner))
    assert booking.reload.payment_refunded?, "an anonymized booking can still be updated"
  end

  test "a blacklisted customer stays blacklisted after deleting their account" do
    profile = CustomerProfile.new(phone: users(:an).phone, note: "Đặt rồi bỏ")
    profile.block(by: users(:owner), reason: "Không đến nhiều lần")
    profile.save!
    sign_in users(:an)

    delete user_registration_path, params: { user: { current_password: "password123" } }

    assert users(:an).reload.deleted_at
    assert profile.reload.blocked?
  end

  test "the owner deletes a customer's or a staff member's account and can cancel a pending deletion; staff cannot" do
    customer = users(:chi)
    booking = courts(:court_one).bookings.create!(user: customer, starts_at: at("18:00"), ends_at: at("19:00"))

    sign_in users(:staffer)
    delete admin_user_path(customer)
    assert_nil customer.reload.deletion_requested_at

    sign_in users(:owner)
    get admin_customer_path(customer.phone)
    assert_select "summary", text: "Xoá tài khoản"
    assert_select "[role=alert]", text: /Còn 1 lượt chưa chơi/

    assert_enqueued_email_with AccountMailer, :deletion_requested, params: ->(params) { params[:by_owner] } do
      delete admin_user_path(customer)
    end
    assert customer.reload.deletion_requested_at
    assert_equal users(:owner), customer.deletion_requested_by
    get admin_customer_path(customer.phone)
    assert_select "[role=status]", text: /Tài khoản đang chờ xoá/

    assert_enqueued_email_with AccountMailer, :deletion_cancelled, params: { email: "chi@example.com", name: "Lê Chi", locale: "vi" } do
      patch cancel_deletion_admin_user_path(customer)
    end
    assert_nil customer.reload.deletion_requested_at
    assert booking.reload.confirmed?

    staff = users(:staffer)
    courts(:court_two).bookings.create!(user: customer, starts_at: at("08:00"), ends_at: at("09:00"))
      .tap { |b| sign_in(staff) && patch(check_in_admin_booking_path(b)) }
    sign_in users(:owner)
    delete admin_user_path(staff)
    assert staff.reload.deleted_at
    assert_equal "Phạm Nhân Viên", staff.full_name, "staff keep their name in the history"
    get admin_staff_members_path
    assert_select "p", text: "Phạm Nhân Viên", count: 0

    checked_in = Booking.find_by!(court: courts(:court_two), starts_at: at("08:00"))
    get admin_booking_path(checked_in)
    assert_select "li", text: /Nhận sân.*Phạm Nhân Viên \(nhân viên, đã nghỉ\)/m

    delete admin_user_path(users(:owner))
    assert_nil users(:owner).reload.deletion_requested_at, "the owner's account cannot be deleted"
  end

  test "a customer downloads everything kept about their account as JSON" do
    sign_in users(:an)
    post bookings_path, params: { booking: { slots: @slots } }
    transfer(Payment.last)

    post account_data_path, params: { current_password: "wrong" }
    assert_redirected_to edit_user_registration_path

    post account_data_path, params: { current_password: "password123" }
    assert_response :success
    assert_equal "application/json", response.media_type
    assert_match(/attachment; filename="vn-badminton-du-lieu-cua-toi-2026-10-19.json"/, response.headers["Content-Disposition"])

    data = response.parsed_body
    assert_equal({ "full_name" => "Nguyễn An", "email" => "an@example.com", "phone" => "+84901234567" }, data["account"].slice("full_name", "email", "phone"))
    booking = data["bookings"].sole
    assert_equal [ "Sân 1", "confirmed", 180_000 ], booking.values_at("court", "status", "amount_vnd")
    assert_equal [ [ "created", "you" ], [ "paid", "system" ] ], booking["history"].map { |e| e.values_at("action", "by") }
    payment = data["payments"].sole
    assert_equal [ "paid", 180_000 ], payment.values_at("status", "amount_vnd")
    assert_equal 180_000, payment["transfers"].sole["amount_vnd"]
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
