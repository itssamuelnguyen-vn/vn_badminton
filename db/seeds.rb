# Seed data for the single venue the app serves. Idempotent: safe to run again with `bin/rails db:seed`.
# The values are assumptions until the real ones are known.

venue = Venue.find_or_create_by!(slug: "vn-badminton") do |v|
  v.name = "VN Badminton"
  v.address = "123 Đường Mẫu, Quận 1, TP. Hồ Chí Minh"
  v.phone = "0901 000 000"
end

# Open every day 05:00-22:00 (minutes since midnight).
(0..6).each do |day|
  venue.opening_hours.find_or_create_by!(day_of_week: day) do |hours|
    hours.opens_minute = OpeningHour.parse_minute("05:00")
    hours.closes_minute = OpeningHour.parse_minute("22:00")
  end
end

(1..10).each do |number|
  venue.courts.find_or_create_by!(name: number.to_s) { |court| court.position = number }
end

[
  { name: "Giờ thường", days_of_week: (0..6).to_a, start_minute: "05:00", end_minute: "22:00", price_per_hour_vnd: 80_000, priority: 0 },
  { name: "Cuối tuần", days_of_week: [ 0, 6 ], start_minute: "05:00", end_minute: "22:00", price_per_hour_vnd: 100_000, priority: 5 },
  { name: "Cao điểm ngày thường", days_of_week: (1..5).to_a, start_minute: "17:00", end_minute: "21:00", price_per_hour_vnd: 120_000, priority: 10 }
].each do |rule|
  venue.price_rules.find_or_create_by!(name: rule[:name]) do |price_rule|
    price_rule.assign_attributes(rule.merge(start_minute: OpeningHour.parse_minute(rule[:start_minute]),
                                            end_minute: OpeningHour.parse_minute(rule[:end_minute])))
  end
end

# The owner account, only when its login is provided: ADMIN_EMAIL=... ADMIN_PASSWORD=... bin/rails db:seed
if ENV["ADMIN_EMAIL"].present?
  User.find_or_create_by!(email: ENV["ADMIN_EMAIL"].strip.downcase) do |user|
    user.full_name = ENV.fetch("ADMIN_NAME", "Chủ sân")
    user.password = ENV.fetch("ADMIN_PASSWORD")
    user.role = :admin
  end
end

# A demo customer and a few bookings so the schedule is not empty in development.
if Rails.env.development? && Booking.none?
  demo = User.find_or_create_by!(email: "khach.demo@example.com") do |user|
    user.full_name = "Khách Demo"
    user.phone = "0900 000 001"
    user.password = "password123"
  end
  courts = venue.courts.to_a
  tomorrow = venue.today + 1

  [ [ 0, "18:00", "20:00" ], [ 1, "17:00", "19:00" ], [ 4, "06:00", "07:30" ], [ 2, "19:30", "21:00" ] ].each do |index, from, to|
    booking = courts[index].bookings.new(user: demo, source: :online,
                                         starts_at: venue.zone.parse("#{tomorrow} #{from}"), ends_at: venue.zone.parse("#{tomorrow} #{to}"))
    puts "Skipped demo booking: #{booking.errors.full_messages.to_sentence}" unless booking.reserve
  end

  maintenance = courts.last.bookings.new(kind: :block, note: "Bảo trì mặt sân",
                                         starts_at: venue.zone.parse("#{tomorrow} 05:00"), ends_at: venue.zone.parse("#{tomorrow} 09:00"))
  puts "Skipped maintenance block: #{maintenance.errors.full_messages.to_sentence}" unless maintenance.reserve
end

puts "Seeded #{venue.name}: #{venue.courts.count} courts, #{venue.price_rules.count} price rules, #{Booking.count} bookings"
