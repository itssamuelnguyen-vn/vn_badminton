module Series
  # One calendar month of a series. Paid at the start of the month for its sessions; sessions cancelled
  # before the payment are simply not billed. Refunds of earlier skipped sessions are taken off.
  #
  #   bill = series.billing(Date.new(2026, 11, 1))
  #   bill.amount_vnd / bill.credit_vnd / bill.due_vnd
  #   bill.mark_paid!(by: owner)   # records the payment and marks the month's sessions paid
  class Billing
    attr_reader :series, :month

    def initialize(series, month)
      @series = series
      @month = month.beginning_of_month
    end

    def period
      @period ||= series.periods.find_by(month: month)
    end

    def paid?
      period.present?
    end

    def sessions
      zone = series.venue.zone
      series.bookings.where(starts_at: zone.local(month.year, month.month, 1)...zone.local(month.next_month.year, month.next_month.month, 1))
            .includes(:court).order(:starts_at, :court_id)
    end

    def billable
      sessions.where.not(status: :cancelled)
    end

    def amount_vnd
      paid? ? period.amount_vnd : billable.sum(:total_amount_vnd)
    end

    # Refunds of skipped sessions not taken off a payment yet, up to this month's amount.
    def credit_vnd
      paid? ? period.credit_vnd : [ available_refunds.sum(:series_refund_vnd), amount_vnd ].min
    end

    def due_vnd
      amount_vnd - credit_vnd
    end

    def mark_paid!(by:, now: Time.current)
      BookingSeries.transaction do
        series.lock!
        raise ArgumentError, "Month already paid" if series.periods.exists?(month: month)

        @period = series.periods.create!(month: month, amount_vnd: amount_vnd, credit_vnd: credit_vnd, paid_at: now, paid_by: by)
        apply_refunds(@period)
        billable.where(payment_status: :unpaid).find_each { |booking| booking.update!(payment_status: :paid, paid_at: now) }
      end
    end

    private

    def available_refunds
      series.bookings.where(series_refund_period_id: nil).where("series_refund_vnd > 0")
    end

    # Takes whole refunds off, oldest first, as far as the credit goes; the rest waits for a later month.
    def apply_refunds(period)
      left = period.credit_vnd
      available_refunds.order(:starts_at).each do |booking|
        break if booking.series_refund_vnd > left

        booking.update_columns(series_refund_period_id: period.id)
        left -= booking.series_refund_vnd
      end
    end
  end
end
