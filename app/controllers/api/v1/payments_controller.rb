module Api
  module V1
    # A payment of the customer: what to transfer (bank, amount still missing, code, VietQR image) and whether it
    # arrived. The app polls it every few seconds while the transfer page is open, and can cancel it before paying.
    class PaymentsController < BaseController
      def show
        payment = Payment.where(user: current_user).find_by!(token: params[:token])
        render json: ApiJson.payment(payment, Venue.main)
      end

      # The customer gives up before transferring (Payment#cancel_by!).
      def cancel
        payment = Payment.where(user: current_user).find_by!(token: params[:token])
        payment.cancel_by!(current_user)
        render json: ApiJson.payment(payment, Venue.main)
      rescue ArgumentError
        render_error :not_allowed, [ t("payments.cancel.not_allowed") ], status: :unprocessable_content
      end
    end
  end
end
