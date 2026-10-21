# Asking the venue for a weekly booking (SeriesRequest, CD-09): the staff create the series or decline it.
# A request still pending can be withdrawn.
class SeriesRequestsController < ApplicationController
  before_action :authenticate_user!

  def new
    tomorrow = Venue.main.today + 1
    @series_request = SeriesRequest.new(starts_on: tomorrow, ends_on: tomorrow.next_month.end_of_month, days_of_week: [ tomorrow.wday ],
                                        start_minute: 1080, end_minute: 1200)
  end

  def create
    attributes = params.require(:series_request).permit(:start_minute, :end_minute, :starts_on, :ends_on, :note, court_ids: [], days_of_week: [])
    attributes[:court_ids] = Array(attributes[:court_ids]).compact_blank.map(&:to_i)
    attributes[:days_of_week] = Array(attributes[:days_of_week]).compact_blank.map(&:to_i)
    @series_request = current_user.series_requests.new(attributes)
    if @series_request.save
      redirect_to series_index_path(anchor: "requests"), notice: t(".success")
    else
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    current_user.series_requests.pending.find(params[:id]).update!(status: :cancelled)
    redirect_to series_index_path(anchor: "requests"), notice: t(".success")
  end
end
