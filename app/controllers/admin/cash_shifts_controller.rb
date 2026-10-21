module Admin
  # The cash drawer per shift ("Ca làm"): staff and the owner open a shift with the cash in the drawer and close
  # it by counting (see CashShift). The history of closed shifts, ?month=2026-10, is for the owner.
  class CashShiftsController < BaseController
    before_action :require_owner, only: :show

    def index
      @shift = CashShift.current(venue)
      @last = CashShift.closed.where(venue_id: venue.id).order(closed_at: :desc).first unless @shift
      load_history if current_user.owner?
    end

    def show
      @shift = CashShift.where(venue_id: venue.id).find(params[:id])
    end

    def create
      shift = CashShift.open!(venue: venue, by: current_user, opening_vnd: amount_param(:opening_vnd))
      if shift.persisted?
        redirect_to admin_cash_shifts_path, notice: t(".success")
      else
        redirect_to admin_cash_shifts_path, alert: shift.errors.full_messages.to_sentence
      end
    end

    def close
      @shift = CashShift.where(venue_id: venue.id).find(params[:id])
      if @shift.close!(by: current_user, counted_vnd: amount_param(:counted_vnd), note: params[:note])
        redirect_to admin_cash_shifts_path, notice: t(".success", difference: helpers.cash_difference(@shift.difference_vnd))
      else
        load_history if current_user.owner?
        render :index, status: :unprocessable_content
      end
    end

    private

    def load_history
      @month = selected_month
      from = venue.zone.local(@month.year, @month.month, 1)
      @history = CashShift.closed.where(venue_id: venue.id, opened_at: from...from.next_month)
                          .includes(:opened_by, :closed_by).order(opened_at: :desc)
    end

    # Typed amounts may carry thousand separators ("1.200.000").
    def amount_param(key)
      Integer(params[key].to_s.delete("., _"), 10, exception: false)
    end

    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      venue.today.beginning_of_month
    end
  end
end
