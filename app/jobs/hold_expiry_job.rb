# Runs when held slots expire (scheduled by BookingBatch#hold): deletes the expired holds of those courts,
# which also refreshes the open schedules, so other customers see the slots free without reloading.
class HoldExpiryJob < ApplicationJob
  queue_as :default

  def perform(court_ids)
    Booking.release_expired_holds!(court_ids)
  end
end
