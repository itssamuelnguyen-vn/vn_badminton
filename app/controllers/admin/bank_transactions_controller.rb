module Admin
  # Money in and out, for the owner: transfers that need a decision (unknown code, wrong amount, late, paid twice),
  # refunds owed after a venue fault, and the transfers matched automatically.
  class BankTransactionsController < BaseController
    before_action :require_owner

    def index
      @needs_review = BankTransaction.needs_review.includes(:payment).order(created_at: :desc)
      @refunds = Booking.where.not(refund_vnd: nil).where(refunded_at: nil).includes(:court).order(:cancelled_at)
      @recent = BankTransaction.where(status: %w[matched resolved]).includes(:payment, :resolved_by).order(created_at: :desc).limit(50)
    end

    # Marks a transfer as reviewed, with what was done (refunded, confirmed by hand, ...).
    def update
      BankTransaction.needs_review.find(params[:id]).resolve!(by: current_user, note: params[:resolution_note])
      redirect_to admin_bank_transactions_path, notice: t(".success")
    end
  end
end
