# The customer's weekly bookings (made by the venue, CD-01) with each month's bill, and "Đóng tiền" for a month
# still due: the transfer code, as the staff send it (CD-03, CD-10). The requests for new ones are listed too.
class SeriesController < ApplicationController
  before_action :authenticate_user!

  def index
    @venue = Venue.main
    @series = BookingSeries.shown_to(current_user, @venue.today).to_a
    @awaiting = Payment.awaiting.where(series: @series).index_by { |payment| [ payment.series_id, payment.series_month ] }
    @requests = current_user.series_requests.order(created_at: :desc).limit(20).to_a
    @courts = Court.where(id: (@series + @requests).flat_map(&:court_ids)).index_by(&:id)
  end

  # ?month=YYYY-MM -> the payment page (the transfer waiting already, or a new one for the amount due).
  def pay
    bill = BookingSeries.where(user: current_user).find(params[:id]).billing(Date.strptime(params.require(:month), "%Y-%m"))
    return redirect_to(series_index_path, alert: t("bookings.create.payments_unavailable")) unless Venue.main.payments_enabled?
    return redirect_to(series_index_path, alert: t(".nothing_due")) unless bill.payable?

    redirect_to payment_path(bill.request_payment!(by: current_user))
  rescue Date::Error
    redirect_to series_index_path, alert: t(".nothing_due")
  end
end
