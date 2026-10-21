module AdminHelper
  # Short money for chart axes: 1500000 -> "1,5tr" ("1.5M" in English).
  def compact_vnd(amount)
    number_to_human(amount, precision: 2, significant: true, format: "%n%u",
                            units: { unit: "", thousand: t("helpers.compact.thousand"), million: t("helpers.compact.million"),
                                     billion: t("helpers.compact.billion") })
  end

  # A round top for a chart axis, at least the value: 5_400_000 -> 6_000_000 (0 -> 1).
  def nice_ceiling(value)
    return 1 unless value.positive?

    power = 10**Math.log10(value).floor
    [ 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10 ].map { |step| (step * power).round }.find { |top| top >= value }
  end

  # Report heatmap shade: none for a closed hour, then lighter to darker green as the occupancy grows.
  def occupancy_shade(occupancy)
    return "bg-transparent" if occupancy.nil?

    [ [ 0, "bg-slate-100" ], [ 0.1, "bg-emerald-100" ], [ 0.25, "bg-emerald-200" ], [ 0.5, "bg-emerald-300" ],
      [ 0.75, "bg-emerald-500" ], [ Float::INFINITY, "bg-emerald-700" ] ]
      .find { |limit, _| occupancy <= limit }.last
  end

  # Change against the previous month, e.g. "+12%" or "−3 điểm %"; nil when there is nothing to compare with.
  def month_change(current, previous, points: false)
    return if current.nil? || previous.nil?

    change = points ? (current - previous) * 100 : (previous.zero? ? nil : (current - previous).fdiv(previous) * 100)
    return if change.nil?

    sign = change.positive? ? "+" : (change.negative? ? "−" : "±")
    number = number_with_precision(change.abs, precision: 1, strip_insignificant_zeros: true)
    [ change, points ? t("helpers.change_points", sign: sign, number: number) : "#{sign}#{number}%" ]
  end

  # A cash shift's difference: "+20.000đ (thừa)", "−10.000đ (thiếu)", "0đ (khớp)".
  def cash_difference(amount)
    key = amount.positive? ? "over" : (amount.negative? ? "short" : "even")
    t("admin.cash_shifts.difference.#{key}", amount: "#{"+" if amount.positive?}#{"−" if amount.negative?}#{format_vnd(amount.abs)}")
  end

  def cash_difference_class(amount)
    amount.zero? ? "text-emerald-700" : (amount.negative? ? "text-red-700" : "text-amber-700")
  end

  # Options for a time select, every 30 minutes: [["05:00", 300], ["05:30", 330], ...]
  def minute_options(range = 0..1440)
    range.step(30).map { |minute| [ OpeningHour.format_minute(minute), minute ] }
  end

  def payment_status_badge(booking)
    classes = {
      "unpaid" => "bg-amber-50 text-amber-700 ring-amber-200",
      "paid" => "bg-emerald-50 text-emerald-700 ring-emerald-200",
      "refunded" => "bg-slate-100 text-slate-700 ring-slate-200"
    }.fetch(booking.payment_status)
    tag.span t("admin.payment_statuses.#{booking.payment_status}"), class: "inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium ring-1 #{classes}"
  end

  # Colors of a booking on the day board.
  def board_booking_classes(booking)
    return "bg-amber-100 text-amber-900 ring-amber-300" if booking.kind_block?

    {
      "pending" => "bg-amber-50 text-amber-900 ring-amber-200",
      "confirmed" => "bg-emerald-50 text-emerald-900 ring-emerald-300",
      "checked_in" => "bg-sky-100 text-sky-900 ring-sky-300",
      "completed" => "bg-slate-100 text-slate-700 ring-slate-300",
      "no_show" => "bg-red-50 text-red-800 ring-red-200"
    }.fetch(booking.status)
  end

  def booking_title(booking)
    booking.kind_block? ? (booking.note.presence || t("admin.block")) : booking.customer_name
  end
end
