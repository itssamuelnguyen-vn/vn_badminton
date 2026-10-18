module BookingsHelper
  # 180000 -> "180.000đ" (vi) / "180,000 VND" (en)
  def format_vnd(amount)
    t("helpers.vnd", amount: number_with_delimiter(amount))
  end

  # 90 -> "1h30", 120 -> "2h"
  def format_duration(minutes)
    hours, rest = minutes.divmod(60)
    rest.zero? ? "#{hours}h" : "#{hours}h#{rest.to_s.rjust(2, "0")}"
  end

  # Every day -> "Hằng ngày", [1, 2, 3, 4, 5] -> "Thứ 2 – Thứ 6", [6, 0] -> "Thứ 7, CN".
  # Monday comes first, as on Vietnamese calendars; runs of 3+ consecutive days become a range.
  def format_days(days)
    return t("helpers.every_day") if days.sort == (0..6).to_a

    names = t("date.abbr_day_names")
    monday_first = days.map { |day| (day + 6) % 7 }.sort
    runs = monday_first.slice_when { |a, b| b != a + 1 }.map { |run| run.map { |day| names[(day + 1) % 7] } }
    runs.map { |run| run.size >= 3 ? "#{run.first} – #{run.last}" : run.join(", ") }.join(", ")
  end

  def time_range(from, to)
    "#{l(from, format: :hour_minute)} – #{l(to, format: :hour_minute)}"
  end

  def booking_status_badge(booking)
    classes = {
      "confirmed" => "bg-emerald-50 text-emerald-700 ring-emerald-200",
      "pending" => "bg-amber-50 text-amber-700 ring-amber-200",
      "checked_in" => "bg-sky-50 text-sky-700 ring-sky-200",
      "completed" => "bg-slate-100 text-slate-700 ring-slate-200",
      "cancelled" => "bg-red-50 text-red-700 ring-red-200",
      "no_show" => "bg-red-50 text-red-700 ring-red-200"
    }.fetch(booking.status)
    tag.span t("bookings.statuses.#{booking.status}"), class: "inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 #{classes}"
  end

  # For the owner and staff: the session is over and neither check-in nor no-show was recorded.
  def unrecorded_badge(booking)
    return unless booking.unrecorded?

    tag.span t("bookings.unrecorded"), class: "inline-flex rounded-full bg-amber-50 px-2.5 py-0.5 text-xs font-medium text-amber-800 ring-1 ring-amber-300"
  end
end
