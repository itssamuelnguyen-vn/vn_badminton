# Withdrawing from a tournament (while registration is open; a paid fee is not refunded).
class TournamentEntriesController < ApplicationController
  before_action :authenticate_user!

  def destroy
    entry = current_user.tournament_entries.find(params[:id])
    entry.cancel_by_customer!
    redirect_to tournament_path(entry.tournament), notice: t(".success")
  rescue ArgumentError
    redirect_to tournament_path(entry.tournament), alert: t(".not_allowed")
  end
end
