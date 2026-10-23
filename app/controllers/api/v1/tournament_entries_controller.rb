module Api
  module V1
    # Withdrawing from a tournament (while registration is open; a paid fee is not refunded).
    class TournamentEntriesController < BaseController
      def destroy
        entry = current_user.tournament_entries.find(params[:id])
        entry.cancel_by_customer!
        render json: ApiJson.tournament_details(entry.tournament, entry, viewer: current_user)
      rescue ArgumentError
        render_error :not_allowed, [ t("tournament_entries.destroy.not_allowed") ], status: :unprocessable_content
      end
    end
  end
end
