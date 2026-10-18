module Admin
  # Money in and out, for the owner: transfers that need a decision (unknown code, too little or too much, late, paid twice),
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

    # A transfer without a payment code: the owner finds its payment (by the payment's or a booking's code), and
    # it is then handled like a transfer carrying that code.
    def assign
      transaction = BankTransaction.needs_review.where(payment_id: nil).find(params[:id])
      code = params[:code].to_s.strip.upcase
      payment = Payment.find_by(code: code) || Booking.find_by(code: code)&.payment
      return redirect_to admin_bank_transactions_path, alert: t(".not_found", code: code) unless payment

      Payments::Webhook.settle(transaction, Time.current, payment: payment)
      redirect_to admin_bank_transactions_path, notice: t(transaction.reload.matched? ? ".confirmed" : ".assigned")
    end
  end
end
