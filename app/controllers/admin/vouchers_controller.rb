module Admin
  # Discount codes for online bookings (Voucher). Owner only. A code already used is turned off, not deleted.
  class VouchersController < BaseController
    before_action :require_owner
    before_action :set_voucher, only: %i[edit update]

    def index
      @vouchers = venue.vouchers.order(active: :desc, valid_until: :desc)
      @uses = VoucherRedemption.joins(:payment).where(payments: { status: %w[awaiting paid] }).group(:voucher_id).count
    end

    def new
      @voucher = venue.vouchers.new(kind: "percent", value: 10, valid_from: venue.today, valid_until: venue.today.next_month, per_user_limit: 1)
    end

    def create
      @voucher = venue.vouchers.new(voucher_params)
      if @voucher.save
        redirect_to admin_vouchers_path, notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @voucher.update(voucher_params)
        redirect_to admin_vouchers_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end

    private

    def set_voucher
      @voucher = venue.vouchers.find(params[:id])
    end

    def voucher_params
      permitted = params.require(:voucher).permit(:code, :description, :kind, :value, :max_discount_vnd, :min_amount_vnd, :valid_from, :valid_until,
                                                  :start_minute, :end_minute, :usage_limit, :per_user_limit, :active, days_of_week: [])
      %i[max_discount_vnd usage_limit start_minute end_minute].each { |key| permitted[key] = permitted[key].presence if permitted.key?(key) }
      permitted
    end
  end
end
