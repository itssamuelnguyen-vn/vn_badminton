module Api
  module V1
    # Open play sessions (PlaySession): the coming ones with places left, the customer's own places, and buying
    # places ({ quantity }) paid by transfer. The list is public; buying needs an account with a verified email.
    class PlaySessionsController < BaseController
      include Slots

      skip_before_action :authenticate!, only: :index
      before_action(only: :index) { @current_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1]) }
      before_action :require_verified_email, only: :buy

      def index
        venue = Venue.main
        sessions = PlaySession.preload_seats_taken(venue.play_sessions.listed.to_a)
        mine = current_user ? current_user.play_session_tickets.active.includes(:payment).group_by(&:play_session_id) : {}
        render json: { sessions: sessions.map { |session| ApiJson.play_session(session, mine.fetch(session.id, [])) } }
      end

      def buy
        venue = Venue.main
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless venue.payments_enabled?

        ticket = PlaySessionTicket.buy(venue.play_sessions.find(params[:id]), current_user, params.require(:quantity))
        if ticket.persisted?
          current_user.remember_locale(I18n.locale)
          render json: ApiJson.payment(ticket.payment, venue), status: :created
        else
          render_error :not_bookable, ticket.errors.full_messages, status: :unprocessable_content
        end
      end
    end
  end
end
