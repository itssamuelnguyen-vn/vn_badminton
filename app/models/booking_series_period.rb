# One calendar month of a series, paid at the start of the month: amount_vnd for the month's sessions,
# minus credit_vnd from sessions of earlier months that were skipped and played by someone else.
class BookingSeriesPeriod < ApplicationRecord
  belongs_to :series, class_name: "BookingSeries", inverse_of: :periods
  belongs_to :paid_by, class_name: "User"
  # Paid in cash while a cash shift was open (paid by transfer: nil).
  belongs_to :cash_shift, optional: true
  has_many :applied_refunds, class_name: "Booking", foreign_key: :series_refund_period_id, inverse_of: :series_refund_period,
                             dependent: :restrict_with_error

  def due_vnd
    amount_vnd - credit_vnd
  end
end
