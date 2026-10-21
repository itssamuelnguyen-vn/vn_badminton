module Admin
  # Customers' weekly booking requests from the app (SeriesRequest). Approving one is creating the series from it
  # (Admin::SeriesController#new with request_id); declining tells the customer why.
  class SeriesRequestsController < BaseController
    def decline
      series_request = SeriesRequest.pending.find(params[:id])
      series_request.decline!(params[:decline_reason], by: current_user)
      NoticeMailer.with(series_request: series_request).series_request_decided.deliver_later
      Push.series_request_decided(series_request)
      redirect_to admin_series_index_path, notice: t(".success")
    end
  end
end
