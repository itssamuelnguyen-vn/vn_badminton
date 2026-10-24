# One match of a Tournament (GD-06..08), made by the draw (Tournaments::Draw): in a group (round robin) or in the
# knockout bracket, where the winner moves on to next_match (slot "a" or "b"). A first-round knockout match with
# one side empty is a bye: won at once by the entry present.
#
# The organizers call a match to one of the tournament's courts (shown on its page) and enter the result: the
# games' scores (the winner is who won more games) or a walkover. A result can be corrected while nothing depends
# on it yet.
class TournamentMatch < ApplicationRecord
  MAX_GAMES = 5

  # No scopes from the enum: "group" would hide Relation#group.
  enum :stage, { group: "group", knockout: "knockout" }, validate: true, scopes: false

  belongs_to :tournament
  belongs_to :entry_a, class_name: "TournamentEntry", optional: true
  belongs_to :entry_b, class_name: "TournamentEntry", optional: true
  belongs_to :winner, class_name: "TournamentEntry", optional: true
  belongs_to :next_match, class_name: "TournamentMatch", optional: true
  belongs_to :court, optional: true

  scope :group_stage, -> { where(stage: "group") }
  scope :knockout, -> { where(stage: "knockout") }
  scope :ordered, -> { order(Arel.sql("stage = 'knockout'"), :group_number, :round, :position) }

  def finished? = winner_id.present?
  def bye? = finished? && (entry_a_id.nil? || entry_b_id.nil?)
  def ready? = entry_a_id.present? && entry_b_id.present? && !finished?
  def loser = finished? && !bye? ? ([ entry_a, entry_b ] - [ winner ]).first : nil

  # Games won by each side of these scores: [a, b].
  def self.games_won(scores)
    scores.each_with_object([ 0, 0 ]) { |(a, b), won| won[a > b ? 0 : 1] += 1 }
  end

  def games = self.class.games_won(scores)

  # "21-15, 18-21, 21-19" (from side a), or nil.
  def score_text
    scores.map { |a, b| "#{a}-#{b}" }.join(", ").presence
  end

  # The knockout round's name: final, semi-final, quarter-final, round of 16, else "round N".
  def round_name
    return I18n.t("tournaments.rounds.round", number: round) if group?

    left = tournament.matches.knockout.maximum(:round) - round
    left <= 3 ? I18n.t("tournaments.rounds.#{%w[final semi_final quarter_final last_16][left]}") : I18n.t("tournaments.rounds.round", number: round)
  end

  # Results can change until the next match is played, and for group matches until the knockout is drawn.
  def editable?
    entry_a_id.present? && entry_b_id.present? && tournament.in_progress? &&
      (knockout? ? !next_match&.finished? : !tournament.matches.knockout.exists?)
  end

  # "Playing on Court 3" on the tournament's page; nil clears it.
  def call!(court, now: Time.current)
    raise ArgumentError, "Not ready" unless ready?

    update!(court: court, called_at: court && now)
  end

  # scores: [[21, 15], [18, 21], [21, 19]] from side a; or walkover_winner (an entry of the match). False with
  # errors when the scores do not give a winner.
  def record(scores: [], walkover_winner: nil, now: Time.current)
    return refuse(:base, :not_editable) unless editable?

    if walkover_winner
      return refuse(:base, :invalid_winner) unless walkover_winner.in?([ entry_a, entry_b ])

      result = { winner: walkover_winner, scores: [], walkover: true }
    else
      scores = Array(scores).map { |game| Array(game).map { |points| Integer(points.to_s, exception: false) } }
                            .reject { |game| game.all?(&:nil?) }
      return refuse(:scores, :invalid) unless valid_scores?(scores)

      a, b = self.class.games_won(scores)
      result = { winner: a > b ? entry_a : entry_b, scores: scores, walkover: false }
    end
    transaction do
      update!(**result, finished_at: now)
      next_match&.update!("entry_#{next_slot}" => winner)
      Tournaments::Draw.after_result(tournament, now: now)
    end
    true
  end

  private

  def refuse(attribute, type)
    errors.add(attribute, type)
    false
  end

  def valid_scores?(scores)
    return false unless scores.size.between?(1, MAX_GAMES)
    return false unless scores.all? { |game| game.size == 2 && game.all? { |points| points&.between?(0, 99) } && game[0] != game[1] }

    a, b = self.class.games_won(scores)
    a != b
  end
end
