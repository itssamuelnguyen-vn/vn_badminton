module Api
  module V1
    # Running a tournament's matches, by its creator and organizers (GD-05..06): calling one to a court
    # ({ court_id }, null clears it) and entering its result ({ scores: [[21, 15], …] } from side a, or
    # { walkover: "a" | "b" }, the winner). Answers the tournament's details.
    class TournamentMatchesController < BaseController
      include RunsTournaments

      before_action :set_tournament
      before_action :require_organizer
      before_action { @match = @tournament.matches.find(params[:id]) }

      def call
        court = params[:court_id].presence && @tournament.courts.find(params[:court_id])
        @match.call!(court)
        render_details
      rescue ArgumentError
        render_error :not_ready, [ t("tournament_matches.call.not_ready") ], status: :unprocessable_content
      end

      def update
        walkover = { "a" => @match.entry_a, "b" => @match.entry_b }[params[:walkover]]
        if @match.record(scores: Array(params[:scores]).map { |game| Array(game) }, walkover_winner: walkover)
          render_details
        else
          render_error :invalid, @match.errors.full_messages, status: :unprocessable_content
        end
      end

      private

      def render_details
        render json: ApiJson.tournament_details(@tournament.reload, viewer: current_user)
      end

      def refuse_tournament_action
        render_error :forbidden, [ t("tournaments.not_allowed") ], status: :forbidden
      end
    end
  end
end
