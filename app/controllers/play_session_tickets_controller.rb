# Giving up one's places in an open play session (until the cancellation cutoff; paid ones are not refunded).
class PlaySessionTicketsController < ApplicationController
  before_action :authenticate_user!

  def destroy
    current_user.play_session_tickets.find(params[:id]).cancel_by_customer!
    redirect_to play_sessions_path, notice: t(".success")
  rescue ArgumentError
    redirect_to play_sessions_path, alert: t("bookings.cancel.not_allowed")
  end
end
