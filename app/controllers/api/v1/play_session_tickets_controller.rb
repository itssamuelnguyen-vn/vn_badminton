module Api
  module V1
    # Giving up one's places in an open play session (until the cancellation cutoff; paid ones are not refunded).
    class PlaySessionTicketsController < BaseController
      def destroy
        ticket = current_user.play_session_tickets.find(params[:id])
        ticket.cancel_by_customer!
        render json: ApiJson.ticket(ticket)
      rescue ArgumentError
        render_error :not_allowed, [ t("bookings.cancel.not_allowed") ], status: :unprocessable_content
      end
    end
  end
end
