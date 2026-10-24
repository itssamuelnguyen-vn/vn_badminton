# Running a tournament's matches (GD-05..06), by its creator and organizers: calling one to a court of the
# tournament's bookings (shown on its page) and entering its result (games' scores, or a walkover).
class TournamentMatchesController < ApplicationController
  include RunsTournaments

  before_action :authenticate_user!
  before_action :set_tournament
  before_action :require_organizer
  before_action :set_match

  # court_id blank: no court any more.
  def call
    court = params[:court_id].presence && @tournament.courts.find(params[:court_id])
    @match.call!(court)
    redirect_to tournament_path(@tournament, anchor: helpers.dom_id(@match))
  rescue ArgumentError, ActiveRecord::RecordNotFound
    redirect_to tournament_path(@tournament, anchor: helpers.dom_id(@match)), alert: t(".not_ready")
  end

  # scores: { "0" => { a:, b: }, … } one per game; or walkover: "a" / "b" (the winner).
  def update
    walkover = { "a" => @match.entry_a, "b" => @match.entry_b }[params[:walkover]]
    games = params.fetch(:scores, {})
    scores = games.keys.sort_by(&:to_i).map { |index| games[index].permit(:a, :b).to_h.values_at("a", "b") }
    if @match.record(scores: scores, walkover_winner: walkover)
      redirect_to tournament_path(@tournament, anchor: helpers.dom_id(@match)), notice: t(".success")
    else
      redirect_to tournament_path(@tournament, anchor: helpers.dom_id(@match)), alert: @match.errors.full_messages.to_sentence
    end
  end

  private

  def set_match
    @match = @tournament.matches.find(params[:id])
  end
end
