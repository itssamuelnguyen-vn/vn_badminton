# Who is making the current request, for the booking history (BookingEvent). Set by ApplicationController;
# nil in webhooks and background jobs, which the history shows as the system.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
