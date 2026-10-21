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
        purchase = current_user.package_purchases.find_by(id: params[:package_purchase_id]) if params[:package_purchase_id].present?
        quote = batch.quote(purchase: purchase)
        render json: { court_vnd: quote.court_vnd, items_vnd: quote.items_vnd, discount_vnd: quote.discount_vnd, total_vnd: quote.total_vnd,
                       offer: (quote.offer_kind && { kind: quote.offer_kind, label: quote.offer_label }), messages: quote.messages }
      end
    end
  end
end
