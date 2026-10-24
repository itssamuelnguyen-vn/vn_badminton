require "test_helper"

# Customers' own tournaments in the app's API (GD-01..07), as on the website.
class Api::TournamentsTest < ActionDispatch::IntegrationTest
  include ApiTestHelpers

  test "creates a tournament, adds pairs, draws, enters results; the page is public, actions are the organizers'" do
    token = sign_in_api(users(:an))
    post api_v1_tournaments_path, params: { tournament: { title: "Giải đôi", discipline: "doubles", play_format: "round_robin" } }, headers: auth(token), as: :json
    assert_response :created
    body = response.parsed_body
    assert_equal [ "Giải đôi", "Đôi", "setup", true, true ], body.values_at("title", "event", "status", "creator", "organizer")
    assert_match %r{\A/tournaments/\w{16}/organize/\w{16}\z}, body["organizer_path"]
    tournament = Tournament.find_shared(body["token"])

    post api_v1_tournament_entries_path(tournament), params: { list: "Hùng / Lan\nMinh / Thảo\nTuấn / Hoa" }, headers: auth(token), as: :json
    assert_response :created
    assert_equal [ [ "Hùng", "Lan" ] ], response.parsed_body["entries"].first(1).map { |entry| entry.values_at("name", "partner_name") }

    post draw_api_v1_tournament_path(tournament), headers: auth(token), as: :json
    body = response.parsed_body
    assert_equal [ "in_progress", 3, 1 ], [ body["status"], body["matches"].size, body["groups"].size ]
    match = body["matches"].first
    assert match["editable"]

    patch api_v1_tournament_match_path(tournament, match["id"]), params: { scores: [ [ 21, 19 ], [ 21, 17 ] ] }, headers: auth(token), as: :json
    assert_response :success
    assert_equal [ [ 21, 19 ], [ 21, 17 ] ], response.parsed_body["matches"].find { |row| row["id"] == match["id"] }["scores"]

    # Public, without the organizers' data; others cannot act.
    get api_v1_tournament_path(tournament)
    body = response.parsed_body
    assert_equal [ false, false, nil, [] ], body.values_at("creator", "organizer", "organizer_path", "organizers")
    other = sign_in_api(users(:chi))
    patch api_v1_tournament_match_path(tournament, match["id"]), params: { walkover: "b" }, headers: auth(other), as: :json
    assert_response :forbidden

    # Joining with the organizer link.
    post organize_api_v1_tournament_path(tournament), params: { organizer_token: tournament.organizer_token }, headers: auth(other), as: :json
    assert response.parsed_body["organizer"]
    get api_v1_tournaments_path, headers: auth(other)
    assert_equal [ "Giải đôi", false ], response.parsed_body["tournaments"].sole.values_at("title", "creator")
    delete api_v1_tournament_path(tournament), headers: auth(other), as: :json
    assert_response :forbidden
    delete api_v1_tournament_path(tournament), headers: auth(token), as: :json
    assert_response :no_content
  end
end
