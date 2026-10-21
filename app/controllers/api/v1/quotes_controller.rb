module Api
  module V1
    # What an order will cost before booking it: court price, extras, the best offer (member tier or voucher,
    # Pricing::Offer) or the prepaid hours that would pay it. Nothing is saved.
    #   POST { slots, items, voucher_code, package_purchase_id }
    class QuotesController < BaseController
      include Slots

      def create
        batch = BookingBatch.new(user: current_user, slots: slots_param, items: Array(params[:items]).map { |i| i.permit(:product_id, :quantity).to_h.symbolize_keys },
                                 voucher_code: params[:voucher_code])
        batch.bookings.each(&:quote_price)
        court_vnd = batch.bookings.sum(&:total_amount_vnd)
        purchase = current_user.package_purchases.find_by(id: params[:package_purchase_id]) if params[:package_purchase_id].present?
        package_problem = purchase ? (purchase.problem(batch.bookings) || (:no_items if batch.items_amount_vnd.positive?)) : nil

        if purchase && package_problem.nil?
          render json: { court_vnd: court_vnd, items_vnd: 0, discount_vnd: court_vnd, total_vnd: 0, offer: { kind: "package", label: purchase.display_name },
                         messages: [] }
        else
          offer = batch.offer
          messages = [ offer.voucher_message, (t("booking_batch.errors.package.#{package_problem}") if package_problem) ].compact
          render json: { court_vnd: court_vnd, items_vnd: batch.items_amount_vnd, discount_vnd: offer.discount_vnd,
                         total_vnd: court_vnd - offer.discount_vnd + batch.items_amount_vnd,
                         offer: (offer.kind && { kind: offer.kind, label: offer.label }), messages: messages }
        end
      end
    end
  end
end
