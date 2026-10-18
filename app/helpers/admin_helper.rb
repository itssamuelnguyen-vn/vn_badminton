module AdminHelper
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
