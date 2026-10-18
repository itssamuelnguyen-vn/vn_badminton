module Api
  module V1
    # The picked slots of a hold or booking: { "slots": [{ "court_id": 1, "starts_at": "...", "ends_at": "..." }] }.
    module Slots
      private

      def slots_param
        Array(params.require(:slots)).map { |slot| slot.permit(:court_id, :starts_at, :ends_at).to_h.symbolize_keys }
      end

      # Booking waits for the verified email, as on the web.
      def require_verified_email
        render_error(:email_unverified, [ t("bookings.unverified") ], status: :forbidden) unless current_user.confirmed?
      end
    end
  end
end
