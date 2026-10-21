require "test_helper"

# Open play sessions (places sold per player) and groups of customers who play together.
class Api::CommunityTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers
  include ActionMailer::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
  end

  test "the staff create an open play session that blocks its courts; customers buy places until it is full" do
    session = open_play(capacity: 4)
    assert_equal 2, session.blocks.count
    assert session.blocks.all? { |block| block.kind_block? && block.note == "Giao lưu: Giao lưu tối thứ Ba" }

    get api_v1_play_sessions_path
    listed = response.parsed_body["sessions"].sole
    assert_equal [ "Giao lưu tối thứ Ba", 4, 60_000, [] ], listed.values_at("title", "seats_left", "price_vnd", "my_tickets")

    an = sign_in_api(users(:an))
    post tickets_api_v1_play_session_path(session), params: { quantity: 3 }, headers: auth(an), as: :json
    assert_response :created
    assert_equal [ 180_000, "tickets" ], response.parsed_body.values_at("amount_vnd", "purpose")
    an_payment = Payment.find_by!(token: response.parsed_body["token"])

    chi = sign_in_api(users(:chi))
    post tickets_api_v1_play_session_path(session), params: { quantity: 2 }, headers: auth(chi), as: :json
    assert_response :unprocessable_content
    assert_equal [ "Buổi này chỉ còn 1 chỗ." ], response.parsed_body["messages"]

    transfer(an_payment)
    get api_v1_play_sessions_path, headers: auth(an)
    mine = response.parsed_body["sessions"].sole
    assert_equal [ 1, "confirmed", true ], [ mine["seats_left"], mine["my_tickets"].sole["status"], mine["my_tickets"].sole["cancel_without_refund"] ]

    # A place waiting for a transfer is given back when the time is up.
    post tickets_api_v1_play_session_path(session), params: { quantity: 1 }, headers: auth(chi), as: :json
    assert_equal 0, session.seats_left
    travel Payment::WINDOW + Payment::GRACE + 1.minute
    assert_equal 1, session.seats_left

    # A court of a session cannot be booked meanwhile, nor can a session take a booked court.
    post api_v1_hold_path, params: { slots: [ { court_id: courts(:court_one).id, starts_at: at("19:00").iso8601, ends_at: at("20:00").iso8601 } ] },
                           headers: auth(chi), as: :json
    assert_response :unprocessable_content
    sign_in users(:staffer)
    post admin_play_sessions_path, params: { play_session: session_params }
    assert_response :unprocessable_content
  end

  test "a customer gives places back before the cutoff without a refund; the venue cancelling owes paid places back" do
    session = open_play(capacity: 10)
    an = sign_in_api(users(:an))
    post tickets_api_v1_play_session_path(session), params: { quantity: 2 }, headers: auth(an), as: :json
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    chi = sign_in_api(users(:chi))
    post tickets_api_v1_play_session_path(session), params: { quantity: 1 }, headers: auth(chi), as: :json
    transfer(Payment.find_by!(token: response.parsed_body["token"]))

    ticket = users(:chi).play_session_tickets.sole
    delete api_v1_ticket_path(ticket), headers: auth(chi)
    assert_response :success
    assert_equal [ "cancelled", nil ], ticket.reload.values_at(:status, :refund_vnd)
    assert_equal 8, session.seats_left

    sign_in users(:staffer)
    patch cancel_admin_play_session_path(session)
    assert session.reload.cancelled?
    assert session.blocks.all?(&:cancelled?), "the courts are free again"
    paid = users(:an).play_session_tickets.sole
    assert_equal [ "cancelled", 120_000 ], paid.reload.values_at(:status, :refund_vnd)
    assert_enqueued_email_with NoticeMailer, :play_session_cancelled, params: { ticket: paid }

    sign_in users(:owner)
    get admin_play_session_path(session)
    assert_select "p", text: /Cần hoàn 120\.000/
    patch mark_refunded_admin_play_session_path(session, ticket_id: paid.id)
    assert paid.reload.refunded_at
  end

  test "players are checked in on the session page; places count in the monthly report" do
    session = open_play(capacity: 10)
    an = sign_in_api(users(:an))
    post tickets_api_v1_play_session_path(session), params: { quantity: 2 }, headers: auth(an), as: :json
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    ticket = users(:an).play_session_tickets.sole

    sign_in users(:owner)
    patch check_in_admin_play_session_path(session, ticket_id: ticket.id)
    assert ticket.reload.checked_in?
    get admin_reports_path(month: "2026-10")
    assert_select "p", text: /Bán chỗ giao lưu trong tháng: 120\.000/
  end

  test "customers form a group, share bookings with each player's share, and leave it" do
    an = sign_in_api(users(:an))
    post api_v1_groups_path, params: { name: "Cầu lông công ty" }, headers: auth(an), as: :json
    assert_response :created
    code = response.parsed_body["invite_code"]
    group = Group.find(response.parsed_body["id"])

    chi = sign_in_api(users(:chi))
    post join_api_v1_groups_path, params: { code: "WRONG1" }, headers: auth(chi), as: :json
    assert_response :not_found
    post join_api_v1_groups_path, params: { code: code.downcase }, headers: auth(chi), as: :json
    assert_response :success
    assert_equal [ "Lê Chi", "Nguyễn An" ].sort, response.parsed_body["members"].pluck("name").sort

    post api_v1_bookings_path, params: { slots: [ { court_id: courts(:court_one).id, starts_at: at("18:00").iso8601, ends_at: at("19:30").iso8601 } ] },
                               headers: auth(an), as: :json
    transfer(Payment.find_by!(token: response.parsed_body["token"]))
    code_of_booking = users(:an).bookings.sole.code

    post api_v1_group_shares_path(group), params: { booking_code: code_of_booking, players: 4 }, headers: auth(chi), as: :json
    assert_response :not_found, "only your own bookings"
    post api_v1_group_shares_path(group), params: { booking_code: code_of_booking, players: 4 }, headers: auth(an), as: :json
    assert_response :created

    get api_v1_groups_path, headers: auth(chi)
    share = response.parsed_body["groups"].sole["shares"].sole
    assert_equal [ "Nguyễn An", 4, 45_000, 180_000, false ], share.values_at("shared_by", "players", "per_player_vnd", "total_vnd", "mine")
    delete api_v1_group_share_path(group, share["id"]), headers: auth(chi)
    assert_response :forbidden

    delete leave_api_v1_group_path(group), headers: auth(an)
    assert_equal [ users(:chi) ], group.reload.members
    assert_equal users(:chi), group.owner, "the group goes to the oldest member left"
    assert_empty group.shares, "the leaving member's shares go too"
  end

  private

  def open_play(capacity:)
    sign_in users(:staffer)
    post admin_play_sessions_path, params: { play_session: session_params.merge(capacity: capacity) }
    session = PlaySession.last
    assert_redirected_to admin_play_session_path(session)
    sign_out :user
    session
  end

  def session_params
    { title: "Giao lưu tối thứ Ba", court_ids: [ courts(:court_one).id, courts(:court_two).id ], date: "2026-10-20",
      start_minute: 1140, end_minute: 1260, capacity: 8, price_vnd: 60_000, level: "intermediate" }
  end

  def at(time) = Time.zone.parse("2026-10-20 #{time}")
end
