require "test_helper"

# The draw (Tournaments::Draw), results (TournamentMatch#record) and group tables (Tournaments::Standings).
class Tournaments::DrawTest < ActiveSupport::TestCase
  setup do
    travel_to Time.zone.parse("2026-10-19 10:00")
    @venue = venues(:phu_nhuan)
  end

  test "knockout: the bracket is the next power of two, the top seeds get the byes and only meet in the final" do
    tournament = make_tournament(play_format: "knockout")
    entries = enter(tournament, 5)
    entries[0].update!(seed: 1)
    entries[1].update!(seed: 2)
    Tournaments::Draw.call(tournament, random: Random.new(1))

    assert tournament.reload.in_progress?
    assert_equal [ 4, 2, 1 ], (1..3).map { |round| tournament.matches.knockout.where(round: round).count }
    first = tournament.matches.knockout.where(round: 1).order(:position).to_a
    assert_equal entries[0], first.first.entry_a, "seed 1 at the top"
    assert_equal entries[1], first[2].entry_a, "seed 2 in the other half"
    byes = first.select(&:bye?)
    assert_equal 3, byes.size
    assert_includes byes.map(&:winner), entries[0]
    assert_includes byes.map(&:winner), entries[1]
    # Byes move on at once.
    assert_equal entries[0], tournament.matches.knockout.find_by(round: 2, position: 1).entry_a

    play_all(tournament)
    assert tournament.reload.finished?
    assert_equal tournament.matches.knockout.find_by(round: 3).winner, tournament.champion
    assert_equal "Chung kết", tournament.matches.knockout.find_by(round: 3).round_name
  end

  test "round robin: everyone meets everyone once, nobody twice in a round; the table ranks by wins then differences" do
    tournament = make_tournament(play_format: "round_robin", max_entries: 5)
    entries = enter(tournament, 5)
    Tournaments::Draw.call(tournament)

    matches = tournament.matches.to_a
    assert_equal 10, matches.size
    assert_equal 10, matches.map { |match| [ match.entry_a_id, match.entry_b_id ].sort }.uniq.size
    matches.group_by(&:round).each_value do |round|
      players = round.flat_map { |match| [ match.entry_a_id, match.entry_b_id ] }
      assert_equal players.uniq.size, players.size
    end

    # entries[0] wins everything; entries[1] beats the rest.
    matches.each do |match|
      best = [ match.entry_a, match.entry_b ].min_by { |entry| entries.index(entry) }
      match.record(scores: best == match.entry_a ? [ [ 21, 10 ], [ 21, 12 ] ] : [ [ 10, 21 ], [ 12, 21 ] ])
    end
    rows = Tournaments::Standings.new(tournament).groups.fetch(1)
    assert_equal entries, rows.map(&:entry)
    assert_equal [ 4, 4, 0, 8, 0, 80 ], rows.first.then { |row| [ row.played, row.won, row.lost, row.games_for, row.games_against, row.point_difference ] }
    assert tournament.reload.finished?
    assert_equal entries[0], tournament.champion
  end

  test "groups then knockout: seeds spread snake-wise, the best of each group go on without meeting a group-mate first" do
    tournament = make_tournament(play_format: "groups_knockout", group_size: 4, advance_per_group: 2)
    entries = enter(tournament, 8)
    entries.first(4).each.with_index(1) { |entry, seed| entry.update!(seed: seed) }
    Tournaments::Draw.call(tournament)

    assert_equal [ 1, 2, 2, 1 ], entries.first(4).map { |entry| entry.reload.group_number }
    assert_equal 12, tournament.matches.group_stage.count
    assert_empty tournament.matches.knockout

    play_all(tournament, stage: "group")
    semis = tournament.matches.knockout.where(round: 1).to_a
    assert_equal 2, semis.size
    semis.each { |match| assert_not_equal match.entry_a.group_number, match.entry_b.group_number }
    group_match = tournament.matches.group_stage.first
    assert_not group_match.editable?, "groups are settled once the knockout is drawn"

    play_all(tournament)
    assert tournament.reload.finished?
  end

  test "group-mates are kept apart in the first knockout round with three groups too" do
    slots = [ [ 1, 1 ], [ 2, 2 ], [ 3, 3 ], [ 1, 4 ], [ 2, 5 ], [ 3, 6 ] ].map { |group, id| TournamentEntry.new(id: id, group_number: group) }
    bracket = Tournaments::Draw.seed_positions(8).map { |seed| slots[seed - 1] }
    Tournaments::Draw.keep_groups_apart(bracket)
    bracket.each_slice(2) { |a, b| assert_not_equal a.group_number, b.group_number if a && b }
  end

  test "entries still waiting for their transfer are dropped; too few entries cannot be drawn" do
    tournament = make_tournament(play_format: "knockout", fee_vnd: 50_000)
    entry = TournamentEntry.register(tournament, users(:an))
    assert entry.pending?
    error = assert_raises(Tournaments::Draw::Error) { Tournaments::Draw.call(tournament) }
    assert_equal "Cần ít nhất 2 suất đã xác nhận để bốc thăm.", error.message
    assert entry.reload.pending?, "nothing changes when the draw cannot be made"

    enter(tournament, 2)
    Tournaments::Draw.call(tournament)
    assert entry.reload.cancelled?
    assert entry.payment.reload.cancelled?
    assert_equal 1, tournament.matches.count
  end

  test "a result needs a winner by games; a walkover; a knockout result is fixed once the next match is played" do
    tournament = make_tournament(play_format: "knockout")
    enter(tournament, 4)
    Tournaments::Draw.call(tournament)
    semi = tournament.matches.knockout.find_by(round: 1, position: 1)

    assert_not semi.record(scores: [ [ 21, 19 ], [ 19, 21 ] ])
    assert_not semi.record(scores: [ [ 21, 21 ] ])
    assert semi.errors.of_kind?(:scores, :invalid)
    assert semi.record(scores: [ [ 21, 19 ], [ 19, 21 ], [ 21, 18 ] ])
    assert_equal [ semi.entry_a, "21-19, 19-21, 21-18" ], [ semi.winner, semi.score_text ]

    # Corrected: the other side goes on instead.
    assert semi.record(walkover_winner: semi.entry_b)
    final = tournament.matches.knockout.find_by(round: 2)
    assert_equal semi.entry_b, final.entry_a
    tournament.matches.knockout.find_by(round: 1, position: 2).then { |match| match.record(scores: [ [ 21, 3 ] ]) }
    final.reload.record(scores: [ [ 21, 3 ] ])
    assert_not semi.reload.editable?
  end

  private

  def make_tournament(**attributes)
    day = Time.zone.parse("2026-10-25 08:00")
    tournament = @venue.tournaments.new(title: "Giải thử", discipline: "singles", max_entries: 16, fee_vnd: 0, court_ids: [ courts(:court_one).id ],
                                        starts_at: day, ends_at: day + 4.hours, registration_closes_at: day - 1.day, **attributes)
    assert tournament.create_with_blocks(by: users(:staffer)), tournament.errors.full_messages.to_sentence
    tournament
  end

  def enter(tournament, count)
    count.times.map do |i|
      user = User.create!(email: "p#{i}@example.com", full_name: "Người chơi #{i + 1}", phone: format("0912%06d", i), password: "password123")
      tournament.entries.create!(user: user, amount_vnd: 0, status: :confirmed)
    end
  end

  # Side a wins every open match, round by round (the next round fills as results come in).
  def play_all(tournament, stage: nil)
    loop do
      scope = tournament.matches.reload.where(winner_id: nil).where.not(entry_a_id: nil).where.not(entry_b_id: nil)
      scope = scope.where(stage: stage) if stage
      match = scope.order(:round, :position).first
      break unless match

      assert match.record(scores: [ [ 21, 15 ], [ 21, 17 ] ]), match.errors.full_messages.to_sentence
    end
  end
end
