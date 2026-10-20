module Pricing
  # The discount on an online order's court price: the customer's member tier (Loyalty::Tier) or a voucher code,
  # whichever saves more (never both). Extras (TI-01) are never discounted.
  #
  #   offer = Pricing::Offer.best(user:, bookings:, voucher_code: "HE2026")
  #   offer.kind          # => "voucher", "tier" or nil
  #   offer.discount_vnd  # => 20000
  #   offer.voucher_problem # => :expired... when a code was given but cannot be used (the tier still applies)
  Offer = Data.define(:kind, :discount_vnd, :voucher, :tier, :voucher_problem) do
    def self.best(user:, bookings:, voucher_code: nil, venue: Venue.main)
      court_vnd = bookings.sum(&:total_amount_vnd)
      tier = Loyalty::Tier.for(user, venue: venue)
      tier_off = court_vnd * tier.percent / 100 / 1000 * 1000

      voucher = voucher_code.present? ? venue.vouchers.find_code(voucher_code) : nil
      problem = voucher ? voucher.problem(user, bookings, court_vnd) : (:not_found if voucher_code.present?)
      voucher_off = voucher && problem.nil? ? voucher.discount_for(court_vnd) : 0

      if voucher_off.positive? && voucher_off >= tier_off
        new(kind: "voucher", discount_vnd: voucher_off, voucher: voucher, tier: tier, voucher_problem: nil)
      elsif tier_off.positive?
        # A valid code that saves less than the tier: not used, and said so.
        new(kind: "tier", discount_vnd: tier_off, voucher: nil, tier: tier, voucher_problem: problem || (:tier_better if voucher))
      else
        new(kind: nil, discount_vnd: 0, voucher: nil, tier: tier, voucher_problem: problem)
      end
    end

    def voucher_message
      I18n.t("pricing.offer.voucher_problems.#{voucher_problem}") if voucher_problem
    end

    def label
      case kind
      when "tier" then I18n.t("pricing.offer.tier", tier: tier.name, percent: tier.percent)
      when "voucher" then I18n.t("pricing.offer.voucher", code: voucher.code)
      end
    end

    # Spreads the discount over the bookings by court price; the last one takes the rounding.
    def spread(bookings)
      court_vnd = bookings.sum(&:total_amount_vnd)
      left = discount_vnd
      bookings.each_with_index do |booking, index|
        share = index == bookings.size - 1 ? left : (court_vnd.zero? ? 0 : discount_vnd * booking.total_amount_vnd / court_vnd)
        booking.discount_vnd = share
        left -= share
      end
    end
  end
end
