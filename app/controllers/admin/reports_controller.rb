require "csv"

module Admin
  # Monthly revenue and occupancy, for the owner. ?month=2026-10; .csv exports the month's reservations.
  class ReportsController < BaseController
    before_action :require_owner

    def show
      @month = selected_month
      @report = Reports::Month.new(venue: venue, month: @month)

      respond_to do |format|
        format.html
        format.csv { send_data csv(@report), filename: "dat-san-#{@month.strftime("%Y-%m")}.csv", type: "text/csv; charset=utf-8" }
      end
    end

    private

    def selected_month
      Date.strptime(params[:month].to_s, "%Y-%m")
    rescue Date::Error
      venue.today.beginning_of_month
    end

    # With a byte order mark so Excel opens the Vietnamese text correctly.
    def csv(report)
      zone = report.venue.zone
      "﻿" + CSV.generate do |rows|
        rows << %w[code date court start end customer phone source status payment amount_vnd]
        report.reservations.each do |b|
          from, to = b.starts_at.in_time_zone(zone), b.ends_at.in_time_zone(zone)
          rows << [ b.code, from.to_date.iso8601, b.court.display_name, from.strftime("%H:%M"), to.strftime("%H:%M"),
                    b.customer_name, PhoneNumber.to_local(b.customer_phone), b.source, b.status, b.payment_status, b.total_amount_vnd ]
        end
      end
    end
  end
end
