# A transfer reported by SePay, stored once per SePay id (the webhook can be delivered more than once).
# matched: it paid an awaiting payment exactly. needs_review: anything else coming in (unknown code, wrong amount,
# late, already paid), left for the owner. ignored: money going out. resolved: reviewed by the owner.
class BankTransaction < ApplicationRecord
  enum :status, { matched: "matched", needs_review: "needs_review", ignored: "ignored", resolved: "resolved" }, validate: true
  enum :direction, { in: "in", out: "out" }, prefix: :money, validate: true

  belongs_to :payment, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  def resolve!(by:, note:, now: Time.current)
    update!(status: :resolved, resolved_by: by, resolution_note: note.to_s.strip.presence, resolved_at: now)
  end
end
