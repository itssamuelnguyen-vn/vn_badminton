module Api
  module V1
    # A payment of the customer: what to transfer (bank, amount still missing, code, VietQR image) and whether it
    # arrived. The app polls it every few seconds while the transfer page is open.
    class PaymentsController < BaseController
      def show
        payment = Payment.where(user: current_user).find_by!(token: params[:token])
        render json: ApiJson.payment(payment, Venue.main)
      end
    end
  end
end
