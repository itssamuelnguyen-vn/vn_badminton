module Api
  module V1
    # A tournament's players, set by its creator before the draw (GD-03): { list } typed one per line, a seed or a
    # name changed ({ entry: { name, partner_name, seed } }), one removed. Answers the tournament's details.
    class TournamentEntriesController < BaseController
      include RunsTournaments

      before_action :set_tournament
      before_action :require_creator

      def create
        _entries, errors = TournamentEntry.add_list(@tournament, params.require(:list))
        return render_error(:invalid, errors, status: :unprocessable_content) if errors.any?

        render json: ApiJson.tournament_details(@tournament.reload, viewer: current_user), status: :created
      end

      def update
        entry = @tournament.entries.find(params[:id])
        return render_error(:invalid, [ t("tournaments.errors.not_setup") ], status: :unprocessable_content) unless @tournament.entries_editable?
        return render_error(:invalid, entry.errors.full_messages, status: :unprocessable_content) unless entry.update(params.require(:entry).permit(:name, :partner_name, :seed))

        render json: ApiJson.tournament_details(@tournament.reload, viewer: current_user)
      end

      def destroy
        entry = @tournament.entries.find(params[:id])
        return render_error(:invalid, [ t("tournaments.errors.not_setup") ], status: :unprocessable_content) unless @tournament.entries_editable?

        entry.destroy!
        render json: ApiJson.tournament_details(@tournament.reload, viewer: current_user)
      end

      private

      def refuse_tournament_action
        render_error :forbidden, [ t("tournaments.not_allowed") ], status: :forbidden
      end
    end
  end
end
