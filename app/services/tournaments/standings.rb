module Tournaments
  # The group tables of a tournament (round robin, and the groups of groups_knockout), GD-07: for each entry the
  # matches played and won, games and points for and against. Ranked by matches won, then game difference, then
  # point difference, then seed. A walkover counts as a win, without games or points.
  #
  #   Standings.new(tournament).groups # => { 1 => [Row, Row, …], 2 => […] }
  class Standings
    Row = Struct.new(:entry, :played, :won, :games_for, :games_against, :points_for, :points_against) do
      def lost = played - won
      def game_difference = games_for - games_against
      def point_difference = points_for - points_against
    end

    def initialize(tournament)
      @tournament = tournament
    end

    def groups
      @groups ||= begin
        entries = @tournament.entries.confirmed.where.not(group_number: nil).includes(:user, :partner)
        rows = entries.to_h { |entry| [ entry.id, Row.new(entry, 0, 0, 0, 0, 0, 0) ] }
        @tournament.matches.group_stage.where.not(winner_id: nil).find_each { |match| count(match, rows) }
        rows.values.group_by { |row| row.entry.group_number }.sort.to_h.transform_values do |list|
          list.sort_by { |row| [ -row.won, -row.game_difference, -row.point_difference, row.entry.seed || Float::INFINITY, row.entry.id ] }
        end
      end
    end

    private

    def count(match, rows)
      a = rows[match.entry_a_id]
      b = rows[match.entry_b_id]
      return unless a && b

      [ a, b ].each { |row| row.played += 1 }
      rows[match.winner_id].won += 1
      games_a, games_b = match.games
      a.games_for += games_a
      a.games_against += games_b
      b.games_for += games_b
      b.games_against += games_a
      points_a = match.scores.sum(&:first)
      points_b = match.scores.sum(&:last)
      a.points_for += points_a
      a.points_against += points_b
      b.points_for += points_b
      b.points_against += points_a
    end
  end
end
