module Tournaments
  # The group tables of a tournament (round robin, and the groups of groups_knockout), GD-07: for each entry the
  # matches played and won, games and points for and against. Ranked as BWF round robins are (General Competition
  # Regulations): by matches won; two tied → the winner of their match first; three or more tied → by game
  # difference, then point difference (over all their group matches), going back to the match between them whenever
  # only two are left tied; still tied → by seed (instead of drawing lots). A walkover counts as a win, without games
  # or points.
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
        entries = @tournament.entries.where.not(group_number: nil)
        rows = entries.to_h { |entry| [ entry.id, Row.new(entry, 0, 0, 0, 0, 0, 0) ] }
        @winners = {}
        @tournament.matches.group_stage.where.not(winner_id: nil).find_each { |match| count(match, rows) }
        rows.values.group_by { |row| row.entry.group_number }.sort.to_h.transform_values { |list| rank(list, %i[won game_difference point_difference]) }
      end
    end

    private

    # Splits by the first criterion (higher first) and breaks each tie with the rest.
    def rank(rows, criteria)
      return rows if rows.size < 2
      return head_to_head(*rows) if rows.size == 2 && criteria.size < 3
      return by_seed(rows) if criteria.empty?

      criterion, *rest = criteria
      rows.group_by(&criterion).sort_by { |value, _| -value }.flat_map { |_, tied| rank(tied, rest) }
    end

    # Two tied: the winner of the match between them (not played yet: by seed).
    def head_to_head(a, b)
      winner = @winners[[ a.entry.id, b.entry.id ].sort]
      return by_seed([ a, b ]) unless winner

      winner == a.entry.id ? [ a, b ] : [ b, a ]
    end

    def by_seed(rows) = rows.sort_by { |row| [ row.entry.seed || Float::INFINITY, row.entry.id ] }

    def count(match, rows)
      a = rows[match.entry_a_id]
      b = rows[match.entry_b_id]
      return unless a && b

      [ a, b ].each { |row| row.played += 1 }
      @winners[[ match.entry_a_id, match.entry_b_id ].sort] = match.winner_id
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
