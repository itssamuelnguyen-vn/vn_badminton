# Settles the refunds of cancelled series sessions once they are over (see Series::Refunds).
class SeriesRefundJob < ApplicationJob
  queue_as :default

  def perform
    Series::Refunds.settle_due
  end
end
