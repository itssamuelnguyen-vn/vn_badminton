require "test_helper"

# Customers' own tournaments on the web (GD-01..07): a tool for their group, the venue takes no part.
class TournamentsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
  end

  test "a customer creates a tournament, types the players, draws, enters results; anyone with the link follows it" do
    sign_in users(:an)
    get tournaments_path
    assert_select "p", text: /Bạn chưa có giải nào/

    post tournaments_path, params: { tournament: { title: "Giải công ty", discipline: "singles", play_format: "knockout" } }
    tournament = Tournament.last
    assert_redirected_to tournament_path(tournament)
    assert_equal users(:an), tournament.created_by
    assert_match(/\A[A-Za-z0-9]{16}\z/, tournament.share_token)

    post tournament_entries_path(tournament), params: { list: "Hùng\n\n  Lan \nMinh\nThảo\n" }
    assert_equal "Đã thêm 4 người chơi.", flash[:notice]
    assert_equal %w[Hùng Lan Minh Thảo], tournament.entries.map(&:name)
    patch tournament_entry_path(tournament, tournament.entries.first), params: { entry: { seed: 1 } }
    assert_equal 1, tournament.entries.first.reload.seed

    post draw_tournament_path(tournament)
    assert tournament.reload.in_progress?
    # The list cannot change after the draw.
    post tournament_entries_path(tournament), params: { list: "Tuấn" }
    assert_equal "Giải đã bốc thăm, không đổi danh sách người chơi được nữa.", flash[:alert]

    semi = tournament.matches.knockout.find_by(round: 1, position: 1)
    patch tournament_match_path(tournament, semi), params: { scores: { "0" => { a: 21, b: 15 }, "1" => { a: 21, b: 18 } } }
    assert_equal "Đã lưu kết quả.", flash[:notice]
    assert_equal semi.entry_a, semi.reload.winner

    # Anyone with the link, signed in or not, sees the bracket but no form.
    sign_out :user
    get tournament_path(tournament)
    assert_response :success
    assert_select "h1", text: "Giải công ty"
    assert_select "h2", text: "Sơ đồ loại trực tiếp"
    assert_select "#results", count: 0
    patch tournament_match_path(tournament, tournament.matches.knockout.find_by(round: 1, position: 2)), params: { walkover: "a" }
    assert_redirected_to new_user_session_path

    sign_in users(:chi)
    patch tournament_match_path(tournament, tournament.matches.knockout.find_by(round: 1, position: 2)), params: { walkover: "a" }
    assert_equal "Chỉ người tổ chức giải mới làm được việc này.", flash[:alert]
    get tournaments_path
    assert_select "##{dom_id(tournament)}", count: 0, message: "not listed for others"
  end

  test "doubles take pairs one per line; a bad line adds nothing; a round robin is capped" do
    sign_in users(:an)
    tournament = users(:an).tournaments.create!(title: "Giải đôi", discipline: "doubles", play_format: "round_robin")

    post tournament_entries_path(tournament), params: { list: "Hùng / Lan\nMinh" }
    assert_equal "Dòng 2: Tên đồng đội không thể để trắng", flash[:alert]
    assert_equal 0, tournament.entries.count

    post tournament_entries_path(tournament), params: { list: "Hùng / Lan\nMinh & Thảo\nTuấn + Hoa" }
    assert_equal [ "Hùng / Lan", "Minh / Thảo", "Tuấn / Hoa" ], tournament.entries.map(&:display_name)

    post tournament_entries_path(tournament), params: { list: (1..8).map { |i| "A#{i} / B#{i}" }.join("\n") }
    assert_equal "Giải này tối đa 10 người/cặp.", flash[:alert]

    # The event cannot change once players are typed.
    patch tournament_path(tournament), params: { tournament: { discipline: "singles", title: "Giải đôi nam" } }
    assert_equal [ "doubles", "Giải đôi nam" ], tournament.reload.values_at(:discipline, :title)
  end

  test "the organizer link lets a signed-in customer enter results; the creator removes them or makes a new link" do
    tournament = users(:an).tournaments.create!(title: "Giải CLB", discipline: "singles", play_format: "knockout")
    TournamentEntry.add_list(tournament, "Hùng\nLan")
    Tournaments::Draw.call(tournament)
    final = tournament.matches.sole

    get organize_tournament_path(tournament, organizer_token: tournament.organizer_token)
    assert_redirected_to new_user_session_path

    sign_in users(:chi)
    get organize_tournament_path(tournament, organizer_token: "wrong")
    assert_select "p", text: /Link này không còn dùng được/
    get organize_tournament_path(tournament, organizer_token: tournament.organizer_token)
    assert_select "p", text: "Nguyễn An mời bạn cùng nhập tỉ số cho giải này."
    post organize_tournament_path(tournament, organizer_token: tournament.organizer_token)
    assert tournament.organizer?(users(:chi))
    get tournaments_path
    assert_select "##{dom_id(tournament)}", text: /Bạn giúp Nguyễn An nhập tỉ số/

    # Organizers enter results but do not set the tournament up.
    get tournament_path(tournament)
    assert_select "#results"
    assert_select "#organizers", count: 0
    delete tournament_path(tournament)
    assert_equal "Chỉ người tổ chức giải mới làm được việc này.", flash[:alert]
    patch tournament_match_path(tournament, final), params: { scores: { "0" => { a: 15, b: 21 }, "1" => { a: 18, b: 21 } } }
    assert tournament.reload.finished?
    get tournament_path(tournament)
    assert_select "p", text: final.reload.entry_b.name, message: "the champion"

    sign_in users(:an)
    old = tournament.organizer_token
    patch organizer_link_tournament_path(tournament)
    assert_not_equal old, tournament.reload.organizer_token
    delete organizers_tournament_path(tournament, user_id: users(:chi).id)
    assert_not tournament.organizer?(users(:chi))
    sign_in users(:chi)
    post organize_tournament_path(tournament, organizer_token: old)
    assert_not tournament.organizer?(users(:chi)), "the old link no longer works"
  end

  test "the creator links their own bookings: courts and date on the page, matches called to those courts" do
    tournament = users(:an).tournaments.create!(title: "Giải sáng CN", discipline: "singles", play_format: "knockout")
    TournamentEntry.add_list(tournament, "Hùng\nLan")
    mine = courts(:court_one).bookings.create!(user: users(:an), starts_at: Time.zone.parse("2026-10-25 08:00"), ends_at: Time.zone.parse("2026-10-25 10:00"))
    other = courts(:court_two).bookings.create!(user: users(:chi), starts_at: Time.zone.parse("2026-10-25 08:00"), ends_at: Time.zone.parse("2026-10-25 10:00"))

    sign_in users(:an)
    patch bookings_tournament_path(tournament), params: { booking_ids: [ mine.id, other.id ] }
    assert_equal tournament, mine.reload.tournament
    assert_nil other.reload.tournament, "only their own bookings"
    assert_equal Date.new(2026, 10, 25), tournament.play_date
    get tournament_path(tournament)
    assert_select "#courts li", text: /Sân 1/

    Tournaments::Draw.call(tournament)
    match = tournament.matches.sole
    patch call_tournament_match_path(tournament, match), params: { court_id: courts(:court_two).id }
    assert_nil match.reload.court, "not a court of the tournament"
    patch call_tournament_match_path(tournament, match), params: { court_id: courts(:court_one).id }
    assert_equal courts(:court_one), match.reload.court
    get tournament_path(tournament)
    assert_select "p", text: /Đang đấu ở Sân 1/

    patch bookings_tournament_path(tournament), params: { booking_ids: [ "" ] }
    assert_nil mine.reload.tournament
  end

  test "deleting a tournament or the creator's account takes its players and results along" do
    tournament = users(:an).tournaments.create!(title: "Giải tạm", discipline: "singles", play_format: "knockout")
    TournamentEntry.add_list(tournament, "Hùng\nLan\nMinh")
    Tournaments::Draw.call(tournament)
    tournament.organizers.create!(user: users(:chi))

    sign_in users(:an)
    delete tournament_path(tournament)
    assert_redirected_to tournaments_path
    assert_not Tournament.exists?(tournament.id)
    assert_equal 0, TournamentEntry.count + TournamentMatch.count + TournamentOrganizer.count

    users(:an).tournaments.create!(title: "Giải khác", discipline: "singles", play_format: "knockout")
    Accounts::Deletion.new(users(:an)).finish!
    assert_equal 0, Tournament.count
  end

  test "a customer has at most 10 tournaments not finished yet" do
    10.times { |i| users(:an).tournaments.create!(title: "Giải #{i}", discipline: "singles", play_format: "knockout") }
    sign_in users(:an)
    post tournaments_path, params: { tournament: { title: "Giải 11", discipline: "singles", play_format: "knockout" } }
    assert_response :unprocessable_content
    assert_select "li", text: /tối đa 10 giải chưa kết thúc/
  end
end
