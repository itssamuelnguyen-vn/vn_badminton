module Payments
  # Handles one SePay webhook delivery (a bank transfer). Stored once per SePay id, so a retried delivery is
  # harmless. A transfer in confirms its payment only when everything matches: the code in the content, the
  # exact amount, and the payment still open. Anything else is kept as "needs review" for the owner.
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

    def self.settle(transaction, now)
      return transaction.update!(status: :ignored) if transaction.money_out?

      code = Payment.code_in(transaction.content)
      payment = code && Payment.find_by(code: code)
      reason = if payment.nil? then "unknown_code"
      elsif payment.paid? then "already_paid"
      elsif transaction.amount_vnd != payment.amount_vnd then "wrong_amount"
      elsif !payment.open?(now) then "late"
      end
      return transaction.update!(payment: payment, review_reason: reason) if reason

      Confirm.call(payment, transaction: transaction, now: now)
      transaction.update!(status: :matched, payment: payment)
    end

    # SePay sends local times ("2026-10-20 18:05:12", Vietnam).
    def self.parse_time(value)
      Time.zone.parse(value.to_s) if value.present?
    end
  end
end
