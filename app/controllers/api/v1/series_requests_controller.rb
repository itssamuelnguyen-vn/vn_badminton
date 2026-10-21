module Api
  module V1
    # Asking the venue for a weekly booking (SeriesRequest): the staff create the series on the web (CD-01).
    #   POST { court_ids: [], days_of_week: [], start_minute, end_minute, starts_on, ends_on, note }
    # DELETE withdraws a series_request still pending.
    class SeriesRequestsController < BaseController
      def index
        render json: { requests: current_user.series_requests.order(created_at: :desc).limit(20).map { |series_request| ApiJson.series_request(series_request) } }
      end

      def create
        series_request = current_user.series_requests.new(params.permit(:start_minute, :end_minute, :starts_on, :ends_on, :note, court_ids: [], days_of_week: []))
        if series_request.save
          render json: ApiJson.series_request(series_request), status: :created
        else
          render_error :invalid, series_request.errors.full_messages, status: :unprocessable_content
        end
      end

      def destroy
        series_request = current_user.series_requests.pending.find(params[:id])
        series_request.update!(status: :cancelled)
        render json: ApiJson.series_request(series_request)
      end
    end
  end
end
