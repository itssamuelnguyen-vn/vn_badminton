# Open play sessions (GL-01..04): the coming ones with places left and the customer's own places. Anyone can see
# the list; buying places (paid by transfer) needs an account with a verified email.
class PlaySessionsController < ApplicationController
  before_action :authenticate_user!, only: :buy
  # Each purchase holds places until its transfer expires; keep that from being used to fill sessions.
  rate_limit to: 10, within: 10.minutes, only: :buy, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { rate_limited(play_sessions_path) }
  before_action :require_verified_email, only: :buy

  def index
    @sessions = PlaySession.preload_seats_taken(Venue.main.play_sessions.listed.to_a)
    @courts = Court.where(id: @sessions.flat_map(&:court_ids)).index_by(&:id)
    @mine = user_signed_in? ? current_user.play_session_tickets.active.includes(:payment, play_session: :venue).group_by(&:play_session_id) : {}
  end

  def buy
    venue = Venue.main
    return redirect_to(play_sessions_path, alert: t("bookings.create.payments_unavailable")) unless venue.payments_enabled?

    ticket = PlaySessionTicket.buy(venue.play_sessions.find(params[:id]), current_user, params.require(:quantity))
    if ticket.persisted?
      current_user.remember_locale(I18n.locale)
      redirect_to payment_path(ticket.payment)
    else
      redirect_to play_sessions_path, alert: ticket.errors.full_messages.to_sentence
    end
  end
end
