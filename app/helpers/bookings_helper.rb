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
    tag.span t("bookings.statuses.#{booking.status}"), class: "inline-flex rounded-full px-2.5 py-0.5 text-xs font-semibold whitespace-nowrap ring-1 #{classes}"
  end


  # One line of the booking history, from the event's action and details (see Booking#record_events).
  def booking_event_text(event)
    d = event.details.symbolize_keys
    scope = "admin.bookings.history"
    case event.action
    when "created" then t("#{scope}.created.#{d[:status] == "pending" ? "held" : "made"}", slot: event_slot(d), amount: format_vnd(d[:amount].to_i),
                         source: t("admin.sources.#{d[:source]}", default: d[:source].to_s))
    when "rescheduled"
      text = t("#{scope}.rescheduled", from: event_slot(d[:from].symbolize_keys), to: event_slot(d[:to].symbolize_keys))
      d[:amount_from] == d[:amount] ? text : "#{text} · #{format_vnd(d[:amount_from].to_i)} → #{format_vnd(d[:amount].to_i)}"
    when "price_changed" then t("#{scope}.price_changed", from: format_vnd(d[:amount_from].to_i), to: format_vnd(d[:amount].to_i))
    when "cancelled" then t("#{scope}.cancelled.#{d[:reason].presence || "plain"}", default: t("#{scope}.cancelled.plain"))
    when "paid" then t("#{scope}.paid.#{d[:via]}", amount: format_vnd(d[:amount].to_i))
    when "payment_undone", "refunded", "refund_due" then t("#{scope}.#{event.action}", amount: format_vnd(d[:amount].to_i))
    else t("#{scope}.#{event.action}")
    end
  end

  # Who did it: the system, the customer of the booking, or a member of staff with their role.
  def booking_event_actor(event)
    actor = event.actor
    if actor.nil? then t("admin.bookings.history.system")
    elsif actor.deleted_at && !actor.manager? then t("admin.bookings.history.deleted_customer")
    elsif actor.deleted_at then t("admin.bookings.history.by_former_staff", name: actor.full_name)
    elsif actor.manager? then t("admin.bookings.history.by_#{actor.role}", name: actor.full_name)
    else t("admin.bookings.history.by_customer", name: actor.full_name)
    end
  end

  private

  def event_slot(details)
    return "" unless details[:starts_at]

    starts_at, ends_at = Time.zone.parse(details[:starts_at]), Time.zone.parse(details[:ends_at])
    "#{details[:court]} · #{l(starts_at.to_date, format: :day_month_year)} #{time_range(starts_at, ends_at)}"
  end
end
