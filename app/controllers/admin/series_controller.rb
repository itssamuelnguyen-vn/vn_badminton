module Admin
  # Regular customers' weekly bookings ("lịch cố định"), paid per calendar month. See BookingSeries.
  class SeriesController < BaseController
    FIELDS = [ :customer_name, :customer_phone, :start_minute, :end_minute, :starts_on, :ends_on, :price_per_hour_vnd, :note,
               { court_ids: [], days_of_week: [] } ].freeze
    MOVE_FIELDS = [ :from, :start_minute, :end_minute, { court_ids: [], days_of_week: [] } ].freeze

    before_action :set_series, only: %i[show extend end_from close_range mark_paid request_payment update_price edit_move preview_move move]

    def index
      @series = BookingSeries.includes(:user).order(ends_on: :desc, customer_name: :asc)
      @requests = SeriesRequest.pending.includes(:user).order(:created_at)
    end

    # ?request_id=: filled in from a customer's request (SeriesRequest), approved when the series is created.
    def new
      today = venue.today
      @request = SeriesRequest.pending.find_by(id: params[:request_id])
      @series = BookingSeries.new(@request&.series_attributes || { starts_on: today, ends_on: today.next_month.end_of_month,
                                                                     days_of_week: [ today.wday ], start_minute: 1080, end_minute: 1200 })
    end

    # Every session checked before anything is saved.
    def preview
      @request = SeriesRequest.pending.find_by(id: params[:request_id])
      @series = build_series
      return render(:new, status: :unprocessable_content) unless @series.valid?

      @plan = Series::Planner.new(@series, from: @series.starts_on, to: @series.ends_on, by: current_user)
    end

    def create
      @series = build_series
      return render(:new, status: :unprocessable_content) unless @series.valid?

      plan = Series::Planner.new(@series, from: @series.starts_on, to: @series.ends_on, by: current_user)
      created = plan.create!
      skipped = plan.sessions.size - created.size
      if (series_request = SeriesRequest.pending.find_by(id: params[:request_id]))
        series_request.approve!(@series, by: current_user)
        NoticeMailer.with(series_request: series_request).series_request_decided.deliver_later
      end
      redirect_to admin_series_path(@series), notice: t(".success", created: created.size, skipped: skipped)
    end

    def show
      @months = @series.months
      @today = venue.today
    end

    # Adds the sessions up to a later end date.
    def extend
      new_end = Date.iso8601(params.require(:ends_on))
      return redirect_to(admin_series_path(@series), alert: t(".not_later")) if new_end <= @series.ends_on

      from = @series.ends_on + 1
      @series.update!(ends_on: new_end)
      created = Series::Planner.new(@series, from: from, to: new_end, by: current_user).create!
      redirect_to admin_series_path(@series), notice: t(".success", count: created.size)
    end

    # Stops the series: sessions from that date are cancelled without refund.
    def end_from
      from = Date.iso8601(params.require(:date))
      count = cancel_sessions(from: from, to: @series.ends_on, reason: BookingSeries::ENDED)
      @series.update!(ends_on: [ from - 1, @series.starts_on ].max)
      redirect_to admin_series_path(@series), notice: t(".success", count: count)
    end

    # The venue is closed (holiday, maintenance): sessions in the range are cancelled and refunded in full.
    def close_range
      count = cancel_sessions(from: Date.iso8601(params.require(:from)), to: Date.iso8601(params.require(:to)), reason: BookingSeries::VENUE_CLOSED)
      redirect_to admin_series_path(@series), notice: t(".success", count: count)
    end

    # A transfer code for the month's amount due (sent to the customer); the webhook marks the month paid.
    def request_payment
      month = Date.iso8601(params.require(:month)).beginning_of_month
      bill = @series.billing(month)
      return redirect_to(admin_series_path(@series), alert: t(".nothing_due")) unless bill.payable?
      return redirect_to(edit_admin_settings_path, alert: t("admin.bookings.create.payments_unavailable")) unless venue.payments_enabled?

      bill.request_payment!(by: current_user)
      redirect_to admin_series_path(@series), notice: t(".success")
    end

    def mark_paid
      @series.billing(Date.iso8601(params.require(:month))).mark_paid!(by: current_user, cash: true)
      @series.payments.awaiting.where(series_month: Date.iso8601(params[:month]).beginning_of_month).find_each { |p| p.update!(status: :cancelled) }
      redirect_to admin_series_path(@series), notice: t(".success")
    rescue ArgumentError
      redirect_to admin_series_path(@series), alert: t(".already_paid")
    end

    # A new agreed price (blank: the price rules) for the sessions still to play in months not paid yet.
    def update_price
      @series.update!(price_per_hour_vnd: params[:price_per_hour_vnd].presence)
      paid_months = @series.periods.pluck(:month)
      sessions = @series.bookings.where.not(status: :cancelled).where("starts_at > ?", Time.current).to_a
      sessions.reject { |b| paid_months.include?(b.starts_at.in_time_zone(venue.zone).to_date.beginning_of_month) }.each(&:reprice!)
      redirect_to admin_series_path(@series), notice: t(".success")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to admin_series_path(@series), alert: e.record.errors.full_messages.to_sentence
    end

    # Moving the sessions to come to other courts or another weekly time (Series::Move): the form, then the plan
    # with every conflict to resolve (skip or another court), then the move. Nothing changes before the last step.
    def edit_move
      @move = Series::Move.blank(@series, by: current_user)
    end

    def preview_move
      @move = build_move
      render :edit_move, status: :unprocessable_content unless @move.valid?
    end

    def move
      @move = build_move
      return render(:edit_move, status: :unprocessable_content) unless @move.valid?

      @move.choices = params.fetch(:choices, {}).permit(*@move.items.map { |item| item.booking.id.to_s }).to_h
      if @move.apply!
        notify_series_moved
        redirect_to admin_series_path(@series), notice: t(".success", count: @move.moved_count)
      else
        render :preview_move, status: :unprocessable_content
      end
    end

    private

    # The customer hears which sessions moved, and how many stayed where they were (CD-11).
    def notify_series_moved
      user = @series.user
      return if user.nil? || user.deleted_at || @move.moved_count.zero?

      NoticeMailer.with(series: @series, sessions: @move.moved_sessions, kept: @move.items.count { |item| item.status == :skipped })
                  .series_moved.deliver_later
    end

    def build_move
      Series::Move.new(@series, by: current_user, **params.require(:move).permit(*MOVE_FIELDS).to_h.symbolize_keys)
    end

    def set_series
      @series = BookingSeries.find(params[:id])
    end

    def build_series
      attributes = params.require(:booking_series).permit(*FIELDS)
      attributes[:court_ids] = Array(attributes[:court_ids]).compact_blank.map(&:to_i)
      attributes[:days_of_week] = Array(attributes[:days_of_week]).compact_blank.map(&:to_i)
      BookingSeries.new(attributes.merge(created_by: current_user))
    end

    def cancel_sessions(from:, to:, reason:)
      zone = venue.zone
      range = zone.local(from.year, from.month, from.day)...zone.local(to.year, to.month, to.day) + 1.day
      sessions = @series.bookings.where(starts_at: range).where(status: %w[confirmed pending]).where("ends_at > ?", Time.current) # not those played
                         .includes(:user, :payment, court: :venue)
      sessions.each { |booking| booking.cancel!(by: current_user, reason: reason) }.size
    end
  end
end
