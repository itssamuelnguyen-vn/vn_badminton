module Admin
  # In-house tournaments (Tournament): created by the owner or staff, who see the entries, set seeds, remove an
  # entry (refunded if paid), make the draw, cancel a tournament (paid entries owed back) and mark refunds done.
  # The matches are run from the tournament's page (TournamentMatchesController).
  class TournamentsController < BaseController
    before_action :set_tournament, except: %i[index new create]
    before_action :set_entry, only: %i[seed remove_entry mark_refunded]

    def index
      now = Time.current
      @upcoming = venue.tournaments.where("ends_at > ?", now).order(:starts_at)
      @past = venue.tournaments.where(ends_at: ..now).order(starts_at: :desc).limit(20)
    end

    def new
      day = venue.today + 7
      @tournament = venue.tournaments.new(starts_at: venue.zone.local(day.year, day.month, day.day, 8), ends_at: venue.zone.local(day.year, day.month, day.day, 12),
                                          registration_closes_at: venue.zone.local(day.year, day.month, day.day) - 1.day + 20.hours,
                                          play_format: "knockout", discipline: "singles", max_entries: 16, fee_vnd: 100_000, group_size: 4, advance_per_group: 2)
    end

    def create
      @tournament = venue.tournaments.new(tournament_params)
      if @tournament.create_with_blocks(by: current_user)
        redirect_to admin_tournament_path(@tournament), notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def show
      @entries = @tournament.entries.includes(:user, :partner, :payment).order(:created_at)
      @matches = @tournament.matches.ordered.includes(:court, :winner, entry_a: %i[user partner], entry_b: %i[user partner]).to_a
      @standings = Tournaments::Standings.new(@tournament).groups unless @tournament.knockout?
    end

    def draw
      Tournaments::Draw.call(@tournament)
      redirect_to admin_tournament_path(@tournament), notice: t(".success")
    rescue Tournaments::Draw::Error => error
      redirect_to admin_tournament_path(@tournament), alert: error.message
    end

    def cancel
      @tournament.cancel!(by: current_user)
      redirect_to admin_tournament_path(@tournament), notice: t(".success")
    rescue ArgumentError
      redirect_to admin_tournament_path(@tournament)
    end

    # Seeds are set before the draw; blank removes it.
    def seed
      @entry.update!(seed: params[:seed].presence&.to_i&.clamp(1, 64)) if @tournament.open?
      redirect_to admin_tournament_path(@tournament)
    end

    # Before the draw only: afterwards the bracket depends on it (a player who cannot come loses by walkover).
    def remove_entry
      @entry.cancel_by_venue! if @tournament.open? && !@entry.cancelled?
      redirect_to admin_tournament_path(@tournament), notice: t(".success")
    end

    def mark_refunded
      @entry.mark_refunded!
      redirect_to admin_tournament_path(@tournament), notice: t(".success")
    rescue ArgumentError
      redirect_to admin_tournament_path(@tournament)
    end

    private

    def set_tournament
      @tournament = venue.tournaments.find(params[:id])
    end

    def set_entry
      @entry = @tournament.entries.find(params[:entry_id])
    end

    # date + start/end minutes and registration_date + registration_minute, as on the open play form.
    def tournament_params
      permitted = params.require(:tournament).permit(:title, :title_en, :description, :play_format, :discipline, :gender, :level, :max_entries,
                                                     :fee_vnd, :group_size, :advance_per_group, :date, :start_minute, :end_minute,
                                                     :registration_date, :registration_minute, court_ids: [])
      date = local_day(permitted.delete(:date))
      start_minute = permitted.delete(:start_minute).to_i
      end_minute = permitted.delete(:end_minute).to_i
      closes = local_day(permitted.delete(:registration_date))
      closes_minute = permitted.delete(:registration_minute).to_i
      if date
        permitted[:starts_at] = date + start_minute.minutes
        permitted[:ends_at] = date + end_minute.minutes
      end
      permitted[:registration_closes_at] = closes + closes_minute.minutes if closes
      permitted[:court_ids] = Array(permitted[:court_ids]).compact_blank.map(&:to_i)
      permitted
    end

    def local_day(value)
      date = Date.iso8601(value.to_s) rescue nil
      date && venue.zone.local(date.year, date.month, date.day)
    end
  end
end
