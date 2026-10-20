require "test_helper"

# The customer mobile app's API: same rules as the web, signed in with a token.
class Api::V1Test < ActionDispatch::IntegrationTest
  include ApiTestHelpers

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @slots = [ { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ]
  end

  test "signs in with a phone number and gets a token; wrong passwords and signed-out calls are refused" do
    post api_v1_session_path, params: { login: "0901 234 567", password: "wrong" }, as: :json
    assert_response :unauthorized
    assert_equal "invalid_login", response.parsed_body["error"]

    token = sign_in_api(users(:an))
    get api_v1_account_path, headers: auth(token)
    assert_response :success
    assert_equal "Nguyễn An", response.parsed_body.dig("user", "full_name")

    delete api_v1_session_path, headers: auth(token)
    get api_v1_account_path, headers: auth(token)
    assert_response :unauthorized
    assert_equal [ "Vui lòng đăng nhập lại." ], response.parsed_body["messages"]
  end

  test "books from the app: schedule, hold, booking, transfer, my bookings, cancel" do
    token = sign_in_api(users(:an))

    get api_v1_schedule_path(date: "2026-10-20"), headers: auth(token)
    assert_response :success
    grid = response.parsed_body
    assert_equal "2026-10-20", grid["date"]
    assert_equal "available", grid.dig("slots", courts(:court_one).id.to_s).find { |s| s["starts_at"] == at("18:00").iso8601 }["state"]

    post api_v1_hold_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ 180_000, (Time.current + Booking::HOLD_DURATION).iso8601 ], response.parsed_body.values_at("amount_vnd", "held_until")

    post api_v1_bookings_path, params: { slots: @slots, note: "Mang vợt" }, headers: auth(token), as: :json
    assert_response :created
    payment = response.parsed_body
    assert_equal [ "awaiting", 180_000, 180_000 ], payment.values_at("status", "amount_vnd", "remaining_vnd")
    assert_match "vietqr.app", payment["qr_image_url"]
    assert_equal "MBBank", payment.dig("bank", "code")

    transfer(Payment.find_by!(token: payment["token"]))
    get api_v1_payment_path(payment["token"]), headers: auth(token)
    assert_equal "paid", response.parsed_body["status"]

    get api_v1_bookings_path, headers: auth(token)
    booking = response.parsed_body["upcoming"].sole
    assert_equal [ "confirmed", "paid", true, true ], booking.values_at("status", "payment_status", "can_cancel", "cancel_without_refund")

    patch cancel_api_v1_booking_path(booking["code"]), headers: auth(token)
    assert_response :success
    assert_equal "cancelled", response.parsed_body["status"]
  end

  test "the booking rules of the web apply: verified email, limits, other customers' payments" do
    unverified = users(:an).tap { |user| user.update_columns(confirmed_at: nil) }
    token = sign_in_api(unverified)
    post api_v1_hold_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_response :forbidden
    assert_equal "email_unverified", response.parsed_body["error"]

    token = sign_in_api(users(:chi))
    too_long = [ @slots.first.merge(ends_at: at("23:00").iso8601) ]
    post api_v1_hold_path, params: { slots: too_long }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_equal "not_bookable", response.parsed_body["error"]
    assert response.parsed_body["messages"].any?

    post api_v1_bookings_path, params: { slots: @slots }, headers: auth(token), as: :json
    other = Payment.last
    get api_v1_payment_path(other.token), headers: auth(sign_in_api(users(:an)))
    assert_response :not_found
  end

  test "signs up from the app; the account page, export and deletion work as on the web" do
    post api_v1_registration_path, params: { full_name: "Trần Bình", phone: "0912 345 678", email: "binh@example.com",
                                             password: "password123", privacy_consent: true }, as: :json
    assert_response :created
    token = response.parsed_body["token"]
    assert_equal false, response.parsed_body.dig("user", "email_verified")

    post api_v1_registration_path, params: { full_name: "X", phone: "0912 000 111", email: "x@example.com", password: "password123" }, as: :json
    assert_response :unprocessable_content, "the privacy consent is required"

    post export_api_v1_account_path, params: { password: "password123" }, headers: auth(token), as: :json
    assert_equal "binh@example.com", response.parsed_body.dig("account", "email")

    delete api_v1_account_path, params: { password: "wrong" }, headers: auth(token), as: :json
    assert_response :forbidden
    delete api_v1_account_path, params: { password: "password123" }, headers: auth(token), as: :json
    assert_response :success
    assert User.find_by!(full_name: Accounts::Deletion::ANONYMOUS_NAME).deleted_at, "nothing booked: deleted at once"
    get api_v1_account_path, headers: auth(token)
    assert_response :unauthorized, "the app is signed out with the account"
  end

  test "edits the optional profile and the profile photo (TK-10)" do
    token = sign_in_api(users(:an))

    patch api_v1_account_path, params: { birth_year: 1995, gender: "female", skill_level: "advanced" }, headers: auth(token), as: :json
    assert_response :success
    assert_equal [ 1995, "female", "advanced", nil ], response.parsed_body["user"].values_at("birth_year", "gender", "skill_level", "avatar_path")

    patch api_v1_account_path, params: { gender: "robot" }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    patch api_v1_account_path, params: { birth_year: 2030 }, headers: auth(token), as: :json
    assert_response :unprocessable_content

    put api_v1_account_avatar_path, params: { avatar: fixture_file_upload("avatar.png", "image/png") }, headers: auth(token)
    assert_response :success
    assert_match %r{\A/rails/active_storage/blobs/}, response.parsed_body.dig("user", "avatar_path")
    assert users(:an).reload.avatar.attached?

    # The type comes from the file itself, not from what the app says.
    text = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "image/png", original_filename: "fake.png")
    put api_v1_account_avatar_path, params: { avatar: text }, headers: auth(token)
    assert_response :unprocessable_content
    assert_equal [ "Ảnh đại diện phải là ảnh JPG, PNG hoặc WebP" ], response.parsed_body["messages"]
    assert_equal "avatar.png", users(:an).reload.avatar.filename.to_s, "the refused photo replaces nothing"

    delete api_v1_account_avatar_path, headers: auth(token)
    assert_response :success
    assert_nil response.parsed_body.dig("user", "avatar_path")
    assert_not users(:an).reload.avatar.attached?
  end

  test "a new password signs the app out; English messages with Accept-Language" do
    token = sign_in_api(users(:an))
    users(:an).update!(password: "newpassword1")
    get api_v1_account_path, headers: auth(token).merge("Accept-Language" => "en")
    assert_response :unauthorized
    assert_equal [ "Please sign in again." ], response.parsed_body["messages"]
  end

  test "the venue and the schedule are public; no management action exists in the API" do
    get api_v1_venue_path
    assert_response :success
    assert_equal courts(:court_one).id, response.parsed_body["courts"].first["id"]

    get api_v1_schedule_path
    assert_response :success

    assert_empty Rails.application.routes.routes.map { |route| route.path.spec.to_s }.grep(%r{\A/api/.*admin})
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
