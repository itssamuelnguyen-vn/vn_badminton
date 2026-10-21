# One line of a booking's history ("Lịch sử" on the admin booking page): who did what and when, recorded by
# Booking itself on every change that matters (see Booking#record_events), so no path can skip it.
# actor: nil for the system (bank transfer webhook, jobs). details: the values needed to tell what changed.
class BookingEvent < ApplicationRecord
  belongs_to :booking
  belongs_to :actor, class_name: "User", optional: true
  # Cash taken at the counter (or its undo) while a cash shift was open; cash_vnd is signed (see CashShift).
  belongs_to :cash_shift, optional: true

  validates :action, presence: true
end
