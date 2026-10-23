require "test_helper"

# In-house tournaments in the app's API: the list and a tournament's page are public; entering pays by transfer.
class Api::TournamentsTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers

  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    day = Time.zone.parse("2026-10-25 08:00")
    @tournament = venues(:phu_nhuan).tournaments.new(title: "Giải đôi", title_en: "Doubles cup", play_format: "round_robin", discipline: "doubles",
                                                      max_entries: 4, fee_vnd: 200_000, court_ids: [ courts(:court_one).id ],
                                                      starts_at: day, ends_at: day + 4.hours, registration_closes_at: day - 1.day)
    assert @tournament.create_with_blocks(by: users(:staffer))
  end

  test "lists tournaments; enters with a partner and pays; the page shows the entry, then the groups and matches once drawn" do
    get api_v1_tournaments_path
    listed = response.parsed_body["tournaments"].sole
    assert_equal [ "Giải đôi", "Đôi", "round_robin", 4, 200_000, true, nil ], listed.values_at("title", "event", "play_format", "spots_left", "fee_vnd", "registration_open", "my_entry")

    token = sign_in_api(users(:an))
    post entries_api_v1_tournament_path(@tournament), params: { partner: { name: "Bình", phone: "0912 345 678" } }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ "tournament", 200_000, true ], response.parsed_body.values_at("purpose", "amount_vnd", "can_cancel")

    get api_v1_tournament_path(@tournament), headers: auth(token)
    mine = response.parsed_body["my_entry"]
    assert_equal [ "Nguyễn An / Bình", "pending", true ], mine.values_at("name", "status", "can_cancel")
    assert mine["payment_token"]

    post entries_api_v1_tournament_path(@tournament), params: { partner: { name: "Chi", phone: "0933 000 111" } }, headers: auth(token), as: :json
    assert_response :unprocessable_content
    assert_equal [ "Bạn hoặc đồng đội đã đăng ký giải này rồi." ], response.parsed_body["messages"]

    transfer(Payment.find_by!(token: mine["payment_token"]))
    chi = sign_in_api(users(:chi))
    post entries_api_v1_tournament_path(@tournament), params: { partner: { name: "Dũng", phone: "0912 000 222" } }, headers: auth(chi), as: :json
    transfer(Payment.find_by!(token: response.parsed_body["token"]))

    Tournaments::Draw.call(@tournament.reload)
    get api_v1_tournament_path(@tournament), headers: { "Accept-Language" => "en" }
    body = response.parsed_body
    assert_equal [ "in_progress", false, nil ], body.values_at("status", "registration_open", "champion")
    assert_equal 2, body["entries"].size
    assert_equal 2, body["groups"].sole["rows"].size
    match = body["matches"].sole
    assert_equal [ "group", 1, false ], match.values_at("stage", "round", "bye")
    assert_equal [ "Nguyễn An / Bình", "Lê Chi / Dũng" ].sort, [ match.dig("a", "name"), match.dig("b", "name") ].sort

    TournamentMatch.find(match["id"]).record(scores: [ [ 21, 12 ], [ 21, 8 ] ])
    get api_v1_tournament_path(@tournament)
    assert_equal "finished", response.parsed_body["status"]
    assert response.parsed_body["champion"]
  end

  test "withdrawing while registration is open; free tournaments confirm at once" do
    @tournament.update!(fee_vnd: 0, discipline: "singles")
    token = sign_in_api(users(:an))
    post entries_api_v1_tournament_path(@tournament), headers: auth(token), as: :json
    assert_response :created
    entry = response.parsed_body["my_entry"]
    assert_equal [ "confirmed", true, nil ], entry.values_at("status", "can_cancel", "payment_token")

    delete api_v1_tournament_entry_path(entry["id"]), headers: auth(token)
    assert_response :success
    assert_nil response.parsed_body["my_entry"]&.dig("can_cancel").presence

    travel_to @tournament.registration_closes_at + 1.minute
    post entries_api_v1_tournament_path(@tournament), headers: auth(token), as: :json
    assert_equal [ "Giải này không còn nhận đăng ký." ], response.parsed_body["messages"]
  end
end
