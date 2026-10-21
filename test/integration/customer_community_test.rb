require "test_helper"

# The app-only features on the web customer pages: open play (GL-01..04), groups (NH-01..03) and weekly
# bookings with their monthly bills and requests (CD-03, CD-09, CD-10).
class CustomerCommunityTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "anyone sees open play sessions; a customer buys places, pays them on the payment page and gives them up" do
    play_session = open_play(capacity: 4)

    get play_sessions_path
    assert_response :success
    assert_select "a", text: "Giao lưu" # in the header
    assert_select "h2", text: "Giao lưu tối thứ Ba"
    assert_select "span", text: "Còn 4/4 chỗ"
    assert_select "a[href='#{new_user_session_path}']", text: "Đăng nhập để đăng ký"
    post buy_play_session_path(play_session), params: { quantity: 2 }
    assert_redirected_to new_user_session_path

    sign_in users(:an)
    get play_sessions_path
    assert_select "select[name=quantity] option", 4
    post buy_play_session_path(play_session), params: { quantity: 3 }
    payment = Payment.last
    assert_redirected_to payment_path(payment)
    assert_equal [ 180_000, "tickets" ], [ payment.amount_vnd, payment.purpose ]
    follow_redirect!
    assert_select "p", text: /Giao lưu: Giao lưu tối thứ Ba .* 3 chỗ/

    get play_sessions_path
    assert_select "span", text: "Còn 1/4 chỗ"
    assert_select "p", text: /Bạn đang giữ 3 chỗ/
    assert_select "a[href='#{payment_path(payment)}']"

    # Over the places left: back to the list with the reason.
    sign_in users(:chi)
    post buy_play_session_path(play_session), params: { quantity: 2 }
    assert_redirected_to play_sessions_path
    assert_equal "Buổi này chỉ còn 1 chỗ.", flash[:alert]

    sign_in users(:an)
    transfer(payment)
    get payment_path(payment)
    assert_select "p", text: /Chỗ giao lưu của bạn đã được xác nhận/
    get play_sessions_path
    assert_select "p", text: /Bạn đã có 3 chỗ/
    ticket = users(:an).play_session_tickets.sole
    delete play_session_ticket_path(ticket)
    assert_redirected_to play_sessions_path
    assert_equal [ "cancelled", nil ], ticket.reload.values_at(:status, :refund_vnd)
    assert_equal 4, play_session.seats_left

    # Past the cancellation cutoff the places cannot be given up.
    post buy_play_session_path(play_session), params: { quantity: 1 }
    transfer(Payment.last)
    travel_to play_session.starts_at - 1.hour
    reset! # the session timed out meanwhile
    sign_in users(:an)
    delete play_session_ticket_path(users(:an).play_session_tickets.confirmed.sole)
    assert_equal "Không thể huỷ lượt đặt này nữa.", flash[:alert]
  end

  test "buying places needs a verified email" do
    play_session = open_play(capacity: 4)
    users(:an).update!(confirmed_at: nil)
    sign_in users(:an)
    post buy_play_session_path(play_session), params: { quantity: 1 }
    assert_redirected_to root_path
    assert_empty PlaySessionTicket.all
  end

  test "customers create and join groups, share bookings from the groups page or the booking page, and leave" do
    sign_in users(:an)
    get bookings_path
    assert_select "a[href='#{groups_path}']", text: /Nhóm/
    assert_select "a[href='#{series_index_path}']", text: /Lịch cố định/

    post groups_path, params: { group: { name: "Cầu lông công ty" } }
    group = Group.last
    assert_redirected_to groups_path(anchor: "group_#{group.id}")
    assert_equal [ users(:an) ], group.members

    sign_in users(:chi)
    post join_groups_path, params: { code: "WRONG1" }
    assert_equal "Mã nhóm không đúng.", flash[:alert]
    post join_groups_path, params: { code: group.invite_code.downcase }
    assert_equal [ users(:an), users(:chi) ].sort, group.members.reload.sort

    sign_in users(:an)
    booking = book(users(:an), "18:00", "19:30")
    get groups_path
    assert_select "li", text: /Lê Chi/
    assert_select "select[name='group_share[booking_code]'] option[value='#{booking.code}']"
    post group_shares_path, params: { group_share: { group_id: group.id, booking_code: booking.code, players: 4 } }
    assert_redirected_to groups_path
    share = group.shares.sole
    assert_equal [ 4, users(:an) ], [ share.players, share.shared_by ]

    # The booking page shows where it is shared, and shares it with another group (players default to the members).
    other = Group.create_for(users(:an), "Bạn đại học")
    get booking_path(booking)
    assert_select "p", text: /Đã chia sẻ với Cầu lông công ty: 4 người, mỗi người 45\.000đ/
    post group_shares_path, params: { group_share: { group_id: other.id, booking_code: booking.code, players: "" } },
                            headers: { "Referer" => booking_url(booking) }
    assert_redirected_to booking_url(booking)
    assert_equal 1, other.shares.sole.players

    sign_in users(:chi)
    get groups_path
    assert_select "strong", text: "45.000đ"
    assert_select "button", text: "Gỡ", count: 0 # not the sharer nor the owner
    delete group_share_path(group, share)
    assert_equal "Chỉ người chia sẻ hoặc chủ nhóm mới gỡ được.", flash[:alert]
    post group_shares_path, params: { group_share: { group_id: group.id, booking_code: booking.code } }
    assert_response :not_found, "only your own bookings"

    sign_in users(:an)
    delete leave_group_path(group)
    assert_equal [ users(:chi) ], group.reload.members
    assert_equal users(:chi), group.owner, "the group goes to the oldest member left"
    assert_empty group.shares

    sign_in users(:chi)
    delete group_path(group)
    assert_not Group.exists?(group.id)
  end

  test "a customer asks for a weekly booking, sees it once made, and pays a month from the web" do
    sign_in users(:an)
    get new_series_request_path
    assert_response :success
    post series_requests_path, params: { series_request: { court_ids: [ "", courts(:court_one).id ], days_of_week: [ "", "2" ], start_minute: 1080,
                                                           end_minute: 1200, starts_on: "2026-11-03", ends_on: "2026-11-24", note: "Nhóm công ty" } }
    assert_redirected_to series_index_path(anchor: "requests")
    series_request = users(:an).series_requests.sole
    assert_equal [ [ courts(:court_one).id ], [ 2 ], "pending" ], series_request.values_at(:court_ids, :days_of_week, :status)

    post series_requests_path, params: { series_request: { court_ids: [ "" ], days_of_week: [ "" ], start_minute: 1080, end_minute: 1080,
                                                           starts_on: "2026-10-19", ends_on: "2026-11-24" } }
    assert_response :unprocessable_content
    assert_select "li", text: /phải từ ngày mai trở đi/

    get series_index_path
    assert_select "span", text: "Chờ sân trả lời"

    sign_in users(:staffer)
    post admin_series_index_path, params: { request_id: series_request.id, booking_series: series_request.series_attributes.merge(customer_phone: "0901234567") }
    series = BookingSeries.last

    sign_in users(:an)
    get series_index_path
    assert_select "span", text: "Đã tạo lịch"
    assert_select "p", text: /Tháng 11, 2026/
    assert_select "dd", text: "960.000đ"
    post pay_series_path(series, month: "2026-11")
    payment = series.payments.awaiting.sole
    assert_redirected_to payment_path(payment)
    assert_equal 960_000, payment.amount_vnd
    post pay_series_path(series, month: "2026-11")
    assert_equal [ payment ], series.payments.awaiting.to_a, "the transfer waiting is reused"

    transfer(payment)
    assert series.billing(Date.new(2026, 11, 1)).paid?
    post pay_series_path(series, month: "2026-11")
    assert_equal "Tháng này không còn tiền cần đóng.", flash[:alert]
    get series_index_path
    assert_select "span", text: "Đã đóng"

    # Someone else's series is not found.
    sign_in users(:chi)
    post pay_series_path(series, month: "2026-11")
    assert_response :not_found
  end

  test "a pending request can be withdrawn" do
    sign_in users(:an)
    series_request = users(:an).series_requests.create!(court_ids: [ courts(:court_one).id ], days_of_week: [ 6 ], start_minute: 1080, end_minute: 1200,
                                                        starts_on: "2026-11-07", ends_on: "2026-12-26")
    delete series_request_path(series_request)
    assert_equal "cancelled", series_request.reload.status
    delete series_request_path(series_request)
    assert_response :not_found
  end

  test "the community pages do not query per session, share or request" do
    group = Group.create_for(users(:an), "Cầu lông công ty")
    add_community_rows(group, 1) # with none, the preloading queries (includes) would not run at all
    few = page_queries
    add_community_rows(group, 3, from: 1)
    assert_equal few, page_queries
  end

  private

  # Open play sessions with a place of users(:an), their bookings shared with the group, and their requests.
  def add_community_rows(group, count, from: 0)
    (from...from + count).each do |i|
      play_session = open_play(capacity: 20, date: (Date.new(2026, 10, 20) + i).iso8601)
      PlaySessionTicket.buy(play_session, users(:an), 1)
      group.share(book(users(:an), "08:00", "09:00", date: (Date.new(2026, 10, 20) + i).iso8601), by: users(:an))
      users(:an).series_requests.create!(court_ids: [ courts(:court_one).id ], days_of_week: [ i % 7 ], start_minute: 1080, end_minute: 1200,
                                        starts_on: "2026-11-07", ends_on: "2026-12-26") if i < SeriesRequest::MAX_PENDING
    end
  end

  def page_queries
    sign_in users(:an)
    [ play_sessions_path, groups_path, series_index_path ].to_h do |path|
      count = 0
      counter = ->(*, payload) { count += 1 unless payload[:name] == "SCHEMA" }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get path }
      assert_response :success
      [ path, count ]
    end
  end

  def open_play(capacity:, date: "2026-10-20")
    sign_in users(:staffer)
    post admin_play_sessions_path, params: { play_session: { title: "Giao lưu tối thứ Ba", court_ids: [ courts(:court_one).id, courts(:court_two).id ],
                                                             date: date, start_minute: 1140, end_minute: 1260, capacity: capacity, price_vnd: 60_000 } }
    assert_redirected_to admin_play_session_path(PlaySession.last)
    sign_out :user
    PlaySession.last
  end

  # A paid online booking of the customer (Booking flow: hold, then transfer).
  def book(user, from, to, date: "2026-10-20")
    sign_in user
    slot = { court_id: courts(:court_one).id, starts_at: Time.zone.parse("#{date} #{from}").iso8601, ends_at: Time.zone.parse("#{date} #{to}").iso8601 }
    post bookings_path, params: { booking: { slots: { "0" => slot } } }
    transfer(Payment.last)
    user.bookings.order(:id).last.tap { |booking| assert booking.reload.confirmed? }
  end
end
