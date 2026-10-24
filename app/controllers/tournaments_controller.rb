# The customers' own tournaments (GD-01..): a tool for a group of players, the venue takes no part. Signed-in
# customers see the ones they run (index) and create one. Each tournament's page is open to anyone with its link:
# the creator sets it up there (players, seeds, courts, organizers, draw), the creator and organizers enter results.
class TournamentsController < ApplicationController
  include RunsTournaments

  before_action :authenticate_user!, except: :show
  rate_limit to: 10, within: 1.hour, only: :create, by: -> { current_user.id }, store: RATE_LIMIT_STORE,
             with: -> { rate_limited(tournaments_path) }
  before_action :set_tournament, except: %i[index new create]
  before_action :require_creator, except: %i[index new create show organize join]

  def index
    @tournaments = Tournament.managed_by(current_user).includes(:created_by, bookings: :court).to_a
  end

  def new
    @tournament = Tournament.new(play_format: "knockout", discipline: "singles", group_size: 4, advance_per_group: 2)
  end

  def create
    @tournament = current_user.tournaments.new(tournament_params)
    if @tournament.save
      redirect_to tournament_path(@tournament), notice: t(".success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @creator = @tournament.creator?(current_user)
    @organizer = @tournament.organizer?(current_user)
    @entries = @tournament.entries.to_a
    @matches = @tournament.matches.ordered.includes(:court, :winner, :entry_a, :entry_b).to_a
    @standings = Tournaments::Standings.new(@tournament).groups unless @tournament.knockout?
    @bookings = @tournament.bookings.includes(:court).where.not(status: :cancelled).order(:starts_at).to_a
    @courts = @tournament.courts.to_a if @organizer
    return unless @creator

    @organizers = @tournament.organizers.includes(:user).order(:created_at).to_a
    @linkable = @tournament.linkable_bookings(current_user).to_a
  end

  def edit; end

  def update
    if @tournament.update(tournament_params)
      redirect_to tournament_path(@tournament), notice: t(".success")
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @tournament.destroy!
    redirect_to tournaments_path, notice: t(".success")
  end

  def draw
    Tournaments::Draw.call(@tournament)
    redirect_to tournament_path(@tournament), notice: t(".success")
  rescue Tournaments::Draw::Error => error
    redirect_to tournament_path(@tournament), alert: error.message
  end

  def undo_draw
    @tournament.undo_draw!
    redirect_to tournament_path(@tournament), notice: t(".success")
  rescue ArgumentError
    redirect_to tournament_path(@tournament), alert: t(".not_allowed")
  end

  def link_bookings
    link_own_bookings(params[:booking_ids])
    redirect_to tournament_path(@tournament, anchor: "courts"), notice: t(".success")
  end

  # The organizer link opened: a page to accept it (signed in, see authenticate_user!).
  def organize
    @valid = ActiveSupport::SecurityUtils.secure_compare(@tournament.organizer_token, params[:organizer_token].to_s)
    @already = @tournament.organizer?(current_user)
  end

  def join
    if @tournament.add_organizer(current_user, params[:organizer_token])
      redirect_to tournament_path(@tournament), notice: t(".success")
    else
      redirect_to tournament_path(@tournament), alert: @tournament.errors.full_messages.to_sentence.presence || t(".wrong_link")
    end
  end

  def reset_organizer_link
    @tournament.reset_organizer_token!
    redirect_to tournament_path(@tournament, anchor: "organizers"), notice: t(".success")
  end

  def remove_organizer
    @tournament.organizers.where(user_id: params[:user_id]).delete_all
    redirect_to tournament_path(@tournament, anchor: "organizers"), notice: t(".success")
  end
end
