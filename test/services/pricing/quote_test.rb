require "test_helper"

class Pricing::QuoteTest < ActiveSupport::TestCase
  test "a court-specific rule beats a higher-priority venue-wide rule" do
    court = courts(:court_one)
    venues(:phu_nhuan).price_rules.create!(court:, name: "Sân 1", days_of_week: [ 2 ], start_minute: 1080, end_minute: 1260,
                                           price_per_hour_vnd: 150_000)

    quote = Pricing::Quote.new(court:, starts_at: tuesday("18:00"), ends_at: tuesday("19:00")).call

    assert_equal 150_000, quote.total_vnd
  end

  test "merges consecutive slots priced by the same rule" do
    quote = Pricing::Quote.new(court: courts(:court_two), starts_at: tuesday("06:00"), ends_at: tuesday("08:00")).call

    assert_equal 160_000, quote.total_vnd
    assert_equal 1, quote.breakdown.size
    assert_equal tuesday("08:00").iso8601, quote.breakdown.first["to"]
  end

  test "raises when a slot has no price" do
    price_rules(:standard).update!(active: false)

    assert_raises(Pricing::Quote::NoPriceError) do
      Pricing::Quote.new(court: courts(:court_one), starts_at: tuesday("06:00"), ends_at: tuesday("07:00")).call
    end
  end

  private

  def tuesday(hhmm)
    Time.zone.parse("2026-10-20 #{hhmm}")
  end
end
