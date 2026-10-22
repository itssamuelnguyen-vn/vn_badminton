require "test_helper"

# Push notifications to the app (DeviceToken, Push, PushNotificationJob), with a fake Firebase (FakeFcm).
class Api::PushTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @fcm = Push::Fcm.current = FakeFcm.new
    @slots = [ { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ]
  end

  test "the app registers its token after signing in; it moves with the phone and goes on sign-out or when turned off" do
    token = sign_in_api(users(:an))
    post api_v1_device_tokens_path, params: { token: "fcm-1", platform: "android", app_version: "0.7.0" }, headers: auth(token), as: :json
    assert_response :no_content
    device = DeviceToken.sole
    assert_equal [ users(:an), "android", "0.7.0" ], device.values_at(:user, :platform, :app_version)

    # Sent again (each start, token refresh): still one row.
    post api_v1_device_tokens_path, params: { token: "fcm-1" }, headers: auth(token), as: :json
    assert_equal 1, DeviceToken.count

    post api_v1_device_tokens_path, params: { token: "fcm-1", platform: "ios" }, headers: auth(token), as: :json
    assert_response :unprocessable_content

    # Someone else signs in on the same phone: the token is theirs now.
    other = sign_in_api(users(:chi))
    post api_v1_device_tokens_path, params: { token: "fcm-1" }, headers: auth(other), as: :json
    assert_equal users(:chi), DeviceToken.sole.user

    # Turned off in the app's settings; another customer's token cannot be removed.
    delete api_v1_device_tokens_path, params: { token: "fcm-1" }, headers: auth(token), as: :json
    assert_response :no_content
    assert_equal 1, DeviceToken.count
    delete api_v1_device_tokens_path, params: { token: "fcm-1" }, headers: auth(other), as: :json
    assert_equal 0, DeviceToken.count

    post api_v1_device_tokens_path, params: { token: "fcm-2" }, headers: auth(other), as: :json
    delete api_v1_session_path, headers: auth(other)
    assert_equal 0, DeviceToken.count, "signing out removes the phone's token with the sign-in"

    post api_v1_device_tokens_path, params: { token: "fcm-3" }
    assert_response :unauthorized
  end

  test "a payment received confirms the bookings and tells the phone, in the customer's language, with the booking to open" do
    token = sign_in_api(users(:an))
    post api_v1_device_tokens_path, params: { token: "fcm-an" }, headers: auth(token), as: :json
    post api_v1_bookings_path, params: { slots: @slots }, headers: auth(token), as: :json
    assert_empty @fcm.sent, "nothing for what the customer just did"

    perform_enqueued_jobs(only: PushNotificationJob) { transfer(Payment.find_by!(token: response.parsed_body["token"])) }
    booking = Booking.last
    assert_equal [ { token: "fcm-an", title: "Đã xác nhận đặt sân", body: "Sân 1 lúc 18:00 ngày 20/10/2026. Hẹn gặp bạn ở sân!",
                     data: { path: "/bookings/#{booking.code}" } } ], @fcm.sent

    users(:an).update!(locale: "en")
    sign_in users(:owner)
    perform_enqueued_jobs(only: PushNotificationJob) { patch cancel_admin_booking_path(booking) }
    assert_equal({ token: "fcm-an", title: "The venue cancelled booking #{booking.code}",
                   body: "Court 1 at 18:00 on 20/10/2026. See the email or the app for details.",
                   data: { path: "/bookings/#{booking.code}" } }, @fcm.sent.last)
  end

  test "reminders, free courts and the venue's answers reach the phone; signed-out, idle and deleted accounts get nothing" do
    token = sign_in_api(users(:an))
    post api_v1_device_tokens_path, params: { token: "fcm-an" }, headers: auth(token), as: :json
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    travel_to(Time.zone.parse("2026-10-20 15:05")) { perform_enqueued_jobs(only: PushNotificationJob) { BookingReminderJob.perform_now } }
    assert_equal [ "Sắp đến giờ chơi", "/bookings/#{booking.code}" ], [ @fcm.sent.last[:title], @fcm.sent.last[:data][:path] ]

    entry = users(:an).waitlist_entries.create!(starts_at: at("20:00"), ends_at: at("21:00"))
    blocker = courts(:court_one).bookings.create!(user: users(:chi), starts_at: at("20:00"), ends_at: at("21:00"))
    perform_enqueued_jobs(only: [ WaitlistJob, PushNotificationJob ]) { blocker.cancel!(by: users(:chi)) }
    assert entry.reload.notified_at
    assert_equal [ "Có sân trống", "Có sân trống lúc 20:00 ngày 20/10/2026. Ai đặt trước được trước!", "/" ],
                 [ @fcm.sent.last[:title], @fcm.sent.last[:body], @fcm.sent.last[:data][:path] ]

    series_request = users(:an).series_requests.create!(court_ids: [ courts(:court_one).id ], days_of_week: [ 6 ], start_minute: 1080,
                                                        end_minute: 1200, starts_on: "2026-11-07", ends_on: "2026-12-26")
    sign_in users(:staffer)
    perform_enqueued_jobs(only: PushNotificationJob) do
      patch decline_admin_series_request_path(series_request), params: { decline_reason: "Hết sân" }
    end
    assert_equal "Sân chưa nhận lịch cố định", @fcm.sent.last[:title]

    # Unused for longer than an app sign-in lasts: the phone is no longer signed in.
    sent = @fcm.sent.size
    ApiToken.update_all(last_used_at: Time.current - ApiToken::IDLE_LIMIT - 1.day)
    assert_no_enqueued_jobs(only: PushNotificationJob) { Push.booking_reminder(booking) }

    ApiToken.update_all(last_used_at: Time.current)
    users(:an).update_columns(deletion_requested_at: Time.current)
    assert_no_enqueued_jobs(only: PushNotificationJob) { Push.booking_reminder(booking) }
    assert_equal sent, @fcm.sent.size
  end

  test "a token Firebase no longer knows is deleted; a phone signed out meanwhile is skipped" do
    token = sign_in_api(users(:an))
    post api_v1_device_tokens_path, params: { token: "gone" }, headers: auth(token), as: :json
    @fcm.invalid_tokens << "gone"
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    perform_enqueued_jobs { Push.booking_reminder(booking) }
    assert_equal 1, @fcm.sent.size
    assert_equal 0, DeviceToken.count

    post api_v1_device_tokens_path, params: { token: "fcm-an" }, headers: auth(token), as: :json
    Push.booking_reminder(booking)
    delete api_v1_session_path, headers: auth(token)
    assert_nothing_raised { perform_enqueued_jobs }
    assert_equal 1, @fcm.sent.size
  end

  test "transient Firebase errors are retried; without a service account nothing is sent" do
    token = sign_in_api(users(:an))
    post api_v1_device_tokens_path, params: { token: "fcm-an" }, headers: auth(token), as: :json
    flaky = FakeFcm.new
    def flaky.deliver(**) = raise(Push::Fcm::TransientError, "503")
    Push::Fcm.current = flaky
    booking = courts(:court_one).bookings.create!(user: users(:an), starts_at: at("18:00"), ends_at: at("19:00"))

    Push.booking_reminder(booking)
    assert_enqueued_jobs 1, only: PushNotificationJob
    perform_enqueued_jobs(only: PushNotificationJob)
    assert_enqueued_jobs 1, only: PushNotificationJob # retried later
    assert_equal 1, DeviceToken.count

    clear_enqueued_jobs
    Push::Fcm.current = Push::Fcm::Disabled.new
    assert_no_enqueued_jobs { Push.booking_reminder(booking) }
  end

  private

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
