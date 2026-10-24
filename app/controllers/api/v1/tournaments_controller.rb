module Api
  module V1
    # The customers' own tournaments (Tournament, GD-01..), as on the website: the ones the customer runs, one
    # tournament's page (public, like its link), creating and editing one, the draw, the linked bookings and the
    # organizers. Answers the tournament's details after each change.
    class TournamentsController < BaseController
      include RunsTournaments

      skip_before_action :authenticate!, only: :show
      before_action(only: :show) { @current_token = ApiToken.authenticate(request.authorization.to_s[/\ABearer (.+)\z/, 1]) }
      rate_limit to: 10, within: 1.hour, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE, with: -> { rate_limited }
      before_action :set_tournament, except: %i[index create]
      before_action :require_creator, except: %i[index create show join]

      def index
        tournaments = Tournament.managed_by(current_user).includes(:created_by, bookings: :court)
        render json: { tournaments: tournaments.map { |tournament| ApiJson.tournament(tournament, viewer: current_user) } }
      end

      def show
        render_details
      end

      def create
        @tournament = current_user.tournaments.new(tournament_params)
        if @tournament.save
          render_details status: :created
        else
          render_error :invalid, @tournament.errors.full_messages, status: :unprocessable_content
        end
      end

      def update
        if @tournament.update(tournament_params)
          render_details
        else
          render_error :invalid, @tournament.errors.full_messages, status: :unprocessable_content
        end
      end

      def destroy
        @tournament.destroy!
        head :no_content
      end

      def draw
        Tournaments::Draw.call(@tournament)
        render_details
      rescue Tournaments::Draw::Error => error
        render_error :invalid, [ error.message ], status: :unprocessable_content
      end

      def undo_draw
        @tournament.undo_draw!
        render_details
      rescue ArgumentError
        render_error :not_allowed, [ t("tournaments.undo_draw.not_allowed") ], status: :unprocessable_content
      end

      # { booking_ids: [...] }
      def link_bookings
        link_own_bookings(params[:booking_ids])
        render_details
      end

      # { organizer_token } from the organizer link.
      def join
        if @tournament.add_organizer(current_user, params.require(:organizer_token))
          render_details
        else
          render_error :invalid, @tournament.errors.full_messages.presence || [ t("tournaments.join.wrong_link") ], status: :unprocessable_content
        end
      end

      def reset_organizer_link
        @tournament.reset_organizer_token!
        render_details
      end

      # { user_id }
      def remove_organizer
        @tournament.organizers.where(user_id: params.require(:user_id)).delete_all
        render_details
      end

      private

      def render_details(status: :ok)
        render json: ApiJson.tournament_details(@tournament.reload, viewer: current_user), status: status
      end

      def refuse_tournament_action
        render_error :forbidden, [ t("tournaments.not_allowed") ], status: :forbidden
      end
    end
  end
end
