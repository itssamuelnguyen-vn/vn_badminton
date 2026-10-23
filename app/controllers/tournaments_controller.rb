# In-house tournaments (GD-01..): the list and each tournament's page (entries, groups, bracket, results) are
# public; entering (the fee paid by transfer) needs an account with a verified email.
class TournamentsController < ApplicationController
  before_action :authenticate_user!, only: :enter
  # Each entry holds a place until its transfer expires; keep that from being used to fill tournaments.
  rate_limit to: 10, within: 10.minutes, only: :enter, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { rate_limited(tournaments_path) }
  before_action :require_verified_email, only: :enter

  def index
    @tournaments = Venue.main.tournaments.listed.to_a
    @mine = user_signed_in? ? TournamentEntry.active.where(tournament: @tournaments).merge(player_scope).index_by(&:tournament_id) : {}
  end

  def show
    @tournament = Venue.main.tournaments.find(params[:id])
    @entries = @tournament.entries.confirmed.includes(:user, :partner).order(:created_at)
    @mine = @tournament.entries.active.merge(player_scope).includes(:payment).first if user_signed_in?
    @matches = @tournament.matches.ordered.includes(:court, :winner, entry_a: %i[user partner], entry_b: %i[user partner]).to_a
    @standings = Tournaments::Standings.new(@tournament).groups unless @tournament.knockout?
  end

  def enter
    tournament = Venue.main.tournaments.find(params[:id])
    if tournament.fee_vnd.positive? && !tournament.venue.payments_enabled?
      return redirect_to(tournament_path(tournament), alert: t("bookings.create.payments_unavailable"))
    end

    partner = params.fetch(:partner, {}).permit(:name, :phone, :gender).to_h.symbolize_keys
    entry = TournamentEntry.register(tournament, current_user, partner: partner)
    if entry.persisted?
      current_user.remember_locale(I18n.locale)
      entry.payment ? redirect_to(payment_path(entry.payment)) : redirect_to(tournament_path(tournament), notice: t(".success"))
    else
      redirect_to tournament_path(tournament), alert: entry.errors.full_messages.to_sentence
    end
  end

  private

  # The signed-in customer's entries, as registrant or partner.
  def player_scope
    TournamentEntry.where(user_id: current_user.id).or(TournamentEntry.where(partner_id: current_user.id))
  end
end
