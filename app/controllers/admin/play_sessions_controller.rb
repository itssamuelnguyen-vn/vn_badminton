module Admin
  # Open play sessions (PlaySession): created by the owner or staff, who see the places sold, check players in,
  # cancel a session (paid places owed back) and mark refunds done.
  class PlaySessionsController < BaseController
    before_action :set_session, only: %i[show cancel check_in mark_refunded]

    def index
      now = Time.current
      @upcoming = venue.play_sessions.where("ends_at > ?", now).order(:starts_at)
      @past = venue.play_sessions.where(ends_at: ..now).order(starts_at: :desc).limit(20)
    end

    def new
      day = venue.today + 1
      @session = venue.play_sessions.new(starts_at: venue.zone.local(day.year, day.month, day.day, 19), ends_at: venue.zone.local(day.year, day.month, day.day, 21),
                                         capacity: 16, price_vnd: 60_000)
    end

    def create
      @session = venue.play_sessions.new(session_params)
      if @session.create_with_blocks(by: current_user)
        redirect_to admin_play_session_path(@session), notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def show
      @tickets = @session.tickets.includes(:user, :payment).order(:created_at)
    end

    def cancel
      @session.cancel!(by: current_user)
      redirect_to admin_play_session_path(@session), notice: t(".success")
    rescue ArgumentError
      redirect_to admin_play_session_path(@session)
    end

    def check_in
      ticket = @session.tickets.confirmed.find(params[:ticket_id])
      ticket.update!(checked_in_at: ticket.checked_in? ? nil : Time.current)
      redirect_to admin_play_session_path(@session)
    end

    def mark_refunded
      @session.tickets.find(params[:ticket_id]).mark_refunded!
      redirect_to admin_play_session_path(@session), notice: t(".success")
    rescue ArgumentError
      redirect_to admin_play_session_path(@session)
    end

    private

    def set_session
      @session = venue.play_sessions.find(params[:id])
    end

    # date + start/end minutes, as on the series form.
    def session_params
      permitted = params.require(:play_session).permit(:title, :title_en, :description, :date, :start_minute, :end_minute, :capacity, :price_vnd, :level, court_ids: [])
      date = Date.iso8601(permitted.delete(:date).to_s) rescue nil
      start_minute = permitted.delete(:start_minute).to_i
      end_minute = permitted.delete(:end_minute).to_i
      if date
        day = venue.zone.local(date.year, date.month, date.day)
        permitted[:starts_at] = day + start_minute.minutes
        permitted[:ends_at] = day + end_minute.minutes
      end
      permitted[:court_ids] = Array(permitted[:court_ids]).compact_blank.map(&:to_i)
      permitted
    end
  end
end
