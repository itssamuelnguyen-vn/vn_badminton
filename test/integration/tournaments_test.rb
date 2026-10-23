require "test_helper"

# In-house tournaments on the web (GD-01..09): staff create and run them, customers enter and pay by transfer.
class TournamentsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
    @fcm = Push::Fcm.current
    Push::Fcm.current = FakeFcm.new
  end

  teardown { Push::Fcm.current = @fcm }

  test "staff create a tournament that blocks its courts; customers enter and pay; the page shows the entries" do
    tournament = create_tournament(discipline: "singles", fee_vnd: 100_000)
    assert_equal 2, tournament.blocks.count
    assert tournament.blocks.all? { |block| block.kind_block? && block.note == "Giải đấu: Giải đơn tháng 11" }

    get tournaments_path
    assert_select "##{dom_id(tournament)}", text: /Giải đơn tháng 11.*Đơn · Loại trực tiếp.*Lệ phí 100.000đ/m

    sign_in users(:an)
    post enter_tournament_path(tournament)
    payment = Payment.last
    assert_redirected_to payment_path(payment)
    assert_equal [ "tournament", 100_000 ], [ payment.purpose, payment.amount_vnd ]
    follow_redirect!
    assert_select "p", text: "Lệ phí giải Giải đơn tháng 11 – Nguyễn An"

    post enter_tournament_path(tournament)
    assert_equal "Bạn hoặc đồng đội đã đăng ký giải này rồi.", flash[:alert]

    transfer(payment)
    assert TournamentEntry.last.confirmed?
    get tournament_path(tournament)
    assert_select "p", text: "Bạn đã có suất thi đấu: Nguyễn An."
    assert_select "li", text: "Nguyễn An"

    # Withdrawing while registration is open: no refund.
    delete tournament_entry_path(TournamentEntry.last)
    assert TournamentEntry.last.cancelled?
    assert_nil TournamentEntry.last.refund_vnd
  end

  test "doubles need a partner, linked to their account; gendered events check genders; nobody plays twice" do
    tournament = create_tournament(discipline: "mixed_doubles", fee_vnd: 0)
    sign_in users(:an)

    post enter_tournament_path(tournament), params: { partner: { name: "Lê Chi", phone: "0933 000 111" } }
    assert_equal "Nội dung này chia theo giới tính, vui lòng chọn giới tính trong trang tài khoản trước.", flash[:alert]

    users(:an).update!(gender: "male")
    users(:chi).update!(gender: "male")
    post enter_tournament_path(tournament), params: { partner: { name: "Lê Chi", phone: "0933 000 111", gender: "female" } }
    assert_equal "Đôi nam nữ cần một nam và một nữ.", flash[:alert], "the partner's own profile wins over what is typed"

    users(:chi).update!(gender: "female")
    post enter_tournament_path(tournament), params: { partner: { name: "Chi", phone: "0933 000 111" } }
    assert_redirected_to tournament_path(tournament)
    assert_equal "Đăng ký thành công, bạn đã có suất thi đấu!", flash[:notice]
    entry = TournamentEntry.last
    assert_equal [ "confirmed", users(:chi), "Nguyễn An / Lê Chi" ], [ entry.status, entry.partner, entry.display_name ]
    assert_nil entry.payment, "a free tournament needs no transfer"

    # The partner sees the entry as theirs but cannot enter again.
    sign_in users(:chi)
    get tournament_path(tournament)
    assert_select "p", text: "Bạn đã có suất thi đấu: Nguyễn An / Lê Chi."
    assert_select "form[action='#{tournament_entry_path(entry)}']", count: 0, message: "only the one who entered withdraws"
    post enter_tournament_path(tournament), params: { partner: { name: "Bình", phone: "0912 000 001", gender: "male" } }
    assert_equal "Bạn hoặc đồng đội đã đăng ký giải này rồi.", flash[:alert]

    # In the partner's own data export too.
    post account_data_path, params: { current_password: "password123" }
    assert_equal [ "Nguyễn An / Lê Chi", false ], response.parsed_body["tournament_entries"].sole.values_at("entry", "registered_by_you")
  end

  test "staff draw, call matches to a court (push), enter scores; the public page shows the bracket and the champion" do
    tournament = create_tournament(discipline: "singles", fee_vnd: 0)
    players = [ users(:an), users(:chi), *2.times.map { |i| User.create!(email: "p#{i}@example.com", full_name: "Người #{i}", phone: format("0912%06d", i), password: "password123") } ]
    players.each { |player| tournament.entries.create!(user: player, amount_vnd: 0, status: :confirmed) }
    DeviceToken.create!(user: users(:an), api_token: ApiToken.issue(users(:an), device_name: "Pixel").first, token: "fcm-an", platform: "android", last_seen_at: Time.current)

    sign_in users(:staffer)
    post draw_admin_tournament_path(tournament)
    assert_redirected_to admin_tournament_path(tournament)
    assert tournament.reload.in_progress?

    semi = tournament.matches.knockout.where(round: 1).detect { |match| [ match.entry_a.user, match.entry_b.user ].include?(users(:an)) }
    perform_enqueued_jobs(only: PushNotificationJob) do
      patch call_admin_tournament_match_path(tournament, semi), params: { court_id: courts(:court_two).id }
    end
    assert_equal "Mời vào Sân 2", Push::Fcm.current.sent.sole[:title]
    get admin_tournament_path(tournament)
    assert_select "##{dom_id(semi)}", text: /Đang đấu ở Sân 2/

    patch admin_tournament_match_path(tournament, semi), params: { scores: { "0" => { a: "21", b: "21" } } }
    assert_match "Tỉ số không hợp lệ", flash[:alert]
    patch admin_tournament_match_path(tournament, semi), params: { scores: { "0" => { a: "21", b: "15" }, "1" => { a: "18", b: "21" }, "2" => { a: "21", b: "19" } } }
    assert_equal "21-15, 18-21, 21-19", semi.reload.score_text
    other = tournament.matches.knockout.where(round: 1).where.not(id: semi.id).sole
    patch admin_tournament_match_path(tournament, other), params: { walkover: "b" }
    assert other.reload.walkover
    final = tournament.matches.knockout.find_by(round: 2)
    patch admin_tournament_match_path(tournament, final), params: { scores: { "0" => { a: "21", b: "10" } } }
    assert tournament.reload.finished?

    sign_out :user
    get tournament_path(tournament)
    assert_select "p", text: final.reload.winner.display_name
    assert_select "p", text: "Chung kết"
    assert_select "p", text: "Thắng do đối thủ bỏ cuộc"

    get tournament_path(tournament, locale: "en")
    assert_select "p", text: "Final"
    sign_in users(:staffer)
    get admin_tournaments_path(locale: "en")
    assert_select "a", text: /Men's singles|Singles · Knockout/
    get admin_tournament_path(tournament, locale: "en")
    assert_response :success
  end

  test "groups then knockout on the public page: the group tables and their matches" do
    tournament = create_tournament(discipline: "singles", fee_vnd: 0, play_format: "groups_knockout", group_size: 3, advance_per_group: 1)
    6.times do |i|
      user = User.create!(email: "g#{i}@example.com", full_name: "Người #{i}", phone: format("0913%06d", i), password: "password123")
      tournament.entries.create!(user: user, amount_vnd: 0, status: :confirmed)
    end
    Tournaments::Draw.call(tournament)
    get tournament_path(tournament)
    assert_select "h3", text: "Bảng A"
    assert_select "h3", text: "Bảng B"
    assert_select "table", count: 2
  end

  test "the venue cancels: courts freed, paid entries owed back and told by email; staff remove an entry before the draw" do
    tournament = create_tournament(discipline: "singles", fee_vnd: 100_000)
    sign_in users(:an)
    post enter_tournament_path(tournament)
    transfer(Payment.last)
    sign_in users(:chi)
    post enter_tournament_path(tournament)
    chi_entry = TournamentEntry.last

    sign_in users(:staffer)
    patch remove_entry_admin_tournament_path(tournament, entry_id: chi_entry.id)
    assert chi_entry.reload.cancelled?
    assert_nil chi_entry.refund_vnd, "it was not paid"

    assert_enqueued_emails(1) { patch cancel_admin_tournament_path(tournament) }
    assert tournament.reload.cancelled?
    assert tournament.blocks.all?(&:cancelled?)
    an_entry = tournament.entries.find_by!(user: users(:an))
    assert_equal 100_000, an_entry.refund_vnd

    sign_in users(:owner)
    patch mark_refunded_admin_tournament_path(tournament, entry_id: an_entry.id)
    assert an_entry.reload.refunded_at
  end

  test "the customer gives up on the payment page; a late transfer only counts while registration is open" do
    tournament = create_tournament(discipline: "singles", fee_vnd: 100_000)
    sign_in users(:an)
    post enter_tournament_path(tournament)
    payment = Payment.last
    patch cancel_payment_path(payment)
    assert_redirected_to tournament_path(tournament)
    assert TournamentEntry.last.cancelled?
    assert_equal tournament.max_entries, tournament.spots_left

    post enter_tournament_path(tournament)
    late = Payment.last
    travel_to tournament.registration_closes_at + 1.minute
    transfer(late)
    assert_equal "late", BankTransaction.last.review_reason
    assert TournamentEntry.last.pending?
  end

  private

  def create_tournament(**overrides)
    sign_in users(:staffer)
    get new_admin_tournament_path
    assert_response :success
    params = { title: "Giải đơn tháng 11", play_format: "knockout", discipline: "singles", gender: "", level: "", max_entries: 16, fee_vnd: 100_000,
               group_size: 4, advance_per_group: 2, court_ids: [ courts(:court_one).id, courts(:court_two).id ], date: "2026-10-25",
               start_minute: 480, end_minute: 720, registration_date: "2026-10-24", registration_minute: 1200 }.merge(overrides)
    post admin_tournaments_path, params: { tournament: params }
    tournament = Tournament.last
    assert_redirected_to admin_tournament_path(tournament)
    sign_out :user
    tournament
  end
end
