module Api
  module V1
    # Prepaid hours: the packages on sale and the customer's own (PackagePurchase); buying one gives a transfer.
    class PackagesController < BaseController
      def index
        venue = Venue.main
        purchases = current_user.package_purchases.listed.includes(:package, :payment).order(created_at: :desc)
        render json: { packages: venue.packages.active.order(:price_vnd).map { |package| ApiJson.package(package) },
                       purchases: purchases.map { |purchase| ApiJson.package_purchase(purchase) } }
      end

      def buy
        venue = Venue.main
        return render_error(:payments_unavailable, [ t("bookings.create.payments_unavailable") ], status: :unprocessable_content) unless venue.payments_enabled?

        purchase = PackagePurchase.buy!(current_user, venue.packages.active.find(params[:id]))
        render json: ApiJson.payment(purchase.payment, venue), status: :created
      end
    end
  end
end
