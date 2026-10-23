module Api
  module V1
    # In-house tournaments (Tournament): the list, one tournament with its entries, groups, bracket and results, and
    # entering ({ partner: { name, phone, gender } } for doubles), paid by transfer: answers the payment, or the
    # tournament when it is free. Reading is public; entering needs an account with a verified email.
    class TournamentsController < BaseController
      include Slots

      skip_before_action :authenticate!, only: %i[index show]
      before_action(only: %i[index show]) { @current_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1]) }
      before_action :require_verified_email, only: :enter

      def index
        tournaments = Venue.main.tournaments.listed.to_a
        mine = current_user ? TournamentEntry.active.where(tournament: tournaments).merge(player_scope).index_by(&:tournament_id) : {}
        render json: { tournaments: tournaments.map { |tournament| ApiJson.tournament(tournament, mine[tournament.id], viewer: current_user) } }
      end

      def show
        tournament = Venue.main.tournaments.find(params[:id])
        mine = current_user && tournament.entries.active.merge(player_scope).includes(:payment).first
        render json: ApiJson.tournament_details(tournament, mine, viewer: current_user)
      end

      def enter
        tournament = Venue.main.tournaments.find(params[:id])
        if tournament.fee_vnd.positive? && !tournament.venue.payments_enabled?
          return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content)
        end

        partner = params.fetch(:partner, {}).permit(:name, :phone, :gender).to_h.symbolize_keys
        entry = TournamentEntry.register(tournament, current_user, partner: partner)
        if !entry.persisted?
          render_error :not_open, entry.errors.full_messages, status: :unprocessable_content
        elsif entry.payment
          current_user.remember_locale(I18n.locale)
          render json: ApiJson.payment(entry.payment, tournament.venue), status: :created
        else
          render json: ApiJson.tournament_details(tournament, entry, viewer: current_user), status: :created
        end
      end

      private

      def player_scope
        TournamentEntry.where(user_id: current_user.id).or(TournamentEntry.where(partner_id: current_user.id))
      end
    end
  end
end
