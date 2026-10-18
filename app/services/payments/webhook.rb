module Payments
  # Handles one SePay webhook delivery (a bank transfer). Stored once per SePay id, so a retried delivery is
  # harmless. Transfers carrying a payment's code add up: once they reach its amount the payment is confirmed,
  # even late if its courts are still free (Confirm). Anything else is kept as "needs review" for the owner:
  # no code, too little so far, too much (confirmed, the excess to refund), late with the court gone, paid twice.
  #
  #   Payments::Webhook.process(params)  # => BankTransaction
  module Webhook
    def self.process(data, now: Time.current)
      transaction = BankTransaction.find_by(sepay_id: data["id"]) and return transaction

      transaction = BankTransaction.create!(
        sepay_id: data["id"], direction: data["transferType"] == "out" ? "out" : "in", amount_vnd: data["transferAmount"].to_i,
        content: data["content"], gateway: data["gateway"], account_number: data["accountNumber"],
        reference_code: data["referenceCode"], transacted_at: parse_time(data["transactionDate"]), payload: data,
        status: :needs_review
      )
      settle(transaction, now)
      transaction
    rescue ActiveRecord::RecordNotUnique # the same delivery handled at the same time
      BankTransaction.find_by!(sepay_id: data["id"])
    end

    # Also used by the owner to assign a transfer without a code to its payment.
    def self.settle(transaction, now, payment: nil)
      return transaction.update!(status: :ignored) if transaction.money_out?

      code = Payment.code_in(transaction.content)
      payment ||= code && Payment.find_by(code: code)
      return transaction.update!(review_reason: "unknown_code") if payment.nil?

      payment.with_lock do
        transaction.update!(payment: payment)
        reason = if payment.paid? then "already_paid"
        elsif payment.cancelled? then "cancelled"
        elsif payment.received_vnd < payment.amount_vnd then "underpaid"
        elsif !Confirm.call(payment, transaction: transaction, now: now) then "late"
        end
        next transaction.update!(review_reason: reason) if reason

        # Earlier part payments are settled by this one.
        payment.transfers.needs_review.where(review_reason: "underpaid").update_all(status: "matched", review_reason: nil)
        overpaid = payment.received_vnd > payment.amount_vnd
        transaction.update!(status: overpaid ? :needs_review : :matched, review_reason: ("overpaid" if overpaid))
      end
      # The payment page shows what is still missing.
      Turbo::StreamsChannel.broadcast_refresh_later_to(payment.stream) if transaction.review_reason == "underpaid"
    end

    # SePay sends local times ("2026-10-20 18:05:12", Vietnam).
    def self.parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    end
  end
end
