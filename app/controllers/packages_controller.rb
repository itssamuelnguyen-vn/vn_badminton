# Prepaid hours (UD-04): the packages on sale and the customer's own purchases. Buying one opens the payment page
# (a transfer within PackagePurchase::PAYMENT_WINDOW); the hours are then used on the booking confirmation page.
class PackagesController < ApplicationController
  before_action :authenticate_user!

  def index
    @venue = Venue.main
    @packages = @venue.packages.active.order(:price_vnd)
    @purchases = current_user.package_purchases.listed.includes(:package, :payment).order(created_at: :desc)
  end

  def buy
    venue = Venue.main
    return redirect_to(packages_path, alert: t("bookings.create.payments_unavailable")) unless venue.payments_enabled?

    purchase = PackagePurchase.buy!(current_user, venue.packages.active.find(params[:id]))
    redirect_to payment_path(purchase.payment)
  end
end
