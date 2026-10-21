module Admin
  # Who plays most, who stopped coming, who does not show up (Reports::Customers). For the owner.
  # ?month=2026-10 picks the last month of the period, ?months=3 its length.
  class CustomerReportsController < BaseController
    before_action :require_owner

    def show
      @report = Reports::Customers.new(venue: venue, month: selected_month, months: params[:months].to_i)
    end

    private

    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      venue.today.beginning_of_month
    end
  end
end
