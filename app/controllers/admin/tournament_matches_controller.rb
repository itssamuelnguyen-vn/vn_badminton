module Admin
  # Running a tournament's matches (GD-08): calling one to a court (the players get a push notification) and
  # entering its result (games' scores, or a walkover).
  class TournamentMatchesController < BaseController
    before_action :set_match

    def call
      @match.call!(venue.courts.active.find(params[:court_id]))
      redirect_to admin_tournament_path(@tournament, anchor: dom_id(@match)), notice: t(".success")
    rescue ArgumentError, ActiveRecord::RecordNotFound
      redirect_to admin_tournament_path(@tournament, anchor: dom_id(@match)), alert: t(".not_ready")
    end

    # scores: { "0" => { a:, b: }, … } one per game; or walkover: "a" / "b" (the winner).
    def update
      walkover = { "a" => @match.entry_a, "b" => @match.entry_b }[params[:walkover]]
      games = params.fetch(:scores, {})
      scores = games.keys.sort_by(&:to_i).map { |index| games[index].permit(:a, :b).to_h.values_at("a", "b") }
      if @match.record(scores: scores, walkover_winner: walkover)
        redirect_to admin_tournament_path(@tournament, anchor: dom_id(@match)), notice: t(".success")
      else
        redirect_to admin_tournament_path(@tournament, anchor: dom_id(@match)), alert: @match.errors.full_messages.to_sentence
      end
    end

    private

    def set_match
      @tournament = venue.tournaments.find(params[:tournament_id])
      @match = @tournament.matches.find(params[:id])
    end

    def dom_id(match) = ActionView::RecordIdentifier.dom_id(match)
  end
end
