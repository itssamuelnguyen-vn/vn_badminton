module Admin
  class BoardsController < BaseController
    def show
      @date = selected_date
      @board = Schedule::Board.new(venue: venue, date: @date)
    end

    private

    # Any date can be opened (past days included); a missing or malformed ?date= shows today.
    def selected_date
      Date.iso8601(params[:date].to_s)
    rescue Date::Error
      venue.today
    end
  end
end
