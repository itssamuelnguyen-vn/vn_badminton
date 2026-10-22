# Push notifications to the customer's phones (the mobile app, Firebase Cloud Messaging), sent where the customer
# already gets the matching email, for what the venue or the system did (not for what the customer just did in the
# app). Never marketing. The texts are in the customer's language (User#locale, like the emails), under
# "push.<kind>" in config/locales; data.path is the page the app opens when the notification is tapped.
#
#   Push.booking_cancelled(booking)
#
# Each phone is sent to by its own PushNotificationJob. Nothing is sent to a deleted or locked account, to phones
# signed out, or when pushes are off (Push::Fcm::Disabled).
module Push
  module_function

  def booking_confirmed(bookings)
    booking = bookings.first
    notify(booking.user, :booking_confirmed, path: bookings.one? ? "/bookings/#{booking.code}" : "/bookings",
                                             courts: -> { bookings.map { |b| b.court.display_name }.uniq.to_sentence },
                                             time: booking.starts_at)
  end

  # Paid for something else than bookings: prepaid hours, places in an open play session, a month of a weekly booking.
  def payment_received(payment)
    notify(payment.user, :payment_received, path: "/payments/#{payment.token}", code: payment.code)
  end

  def booking_reminder(booking)
    notify(booking.user, :booking_reminder, path: "/bookings/#{booking.code}", court: -> { booking.court.display_name }, time: booking.starts_at)
  end

  # By the venue (also for its own fault: the email says what is refunded).
  def booking_cancelled(booking)
    notify(booking.user, :booking_cancelled, path: "/bookings/#{booking.code}", code: booking.code,
                                             court: -> { booking.court.display_name }, time: booking.starts_at)
  end

  # By the venue: the new court and time.
  def booking_rescheduled(booking)
    notify(booking.user, :booking_rescheduled, path: "/bookings/#{booking.code}", code: booking.code,
                                               court: -> { booking.court.display_name }, time: booking.starts_at)
  end

  def slot_freed(entry)
    notify(entry.user, :slot_freed, path: "/", time: entry.starts_at)
  end

  def series_request_decided(series_request)
    notify(series_request.user, :"series_request_#{series_request.status}", path: series_request.approved? ? "/bookings" : "/")
  end

  def series_moved(series, count)
    notify(series.user, :series_moved, path: "/bookings", count: count)
  end

  def play_session_cancelled(ticket)
    session = ticket.play_session
    notify(ticket.user, :play_session_cancelled, path: "/", title: -> { session.display_title }, time: session.starts_at)
  end

  # Values are put in the texts in the customer's language: times in the venue's time ("18:00 ngày 20/10/2026"),
  # lambdas called (names that depend on the language, e.g. "Sân 3" / "Court 3").
  def notify(user, kind, path:, **values)
    return if user.nil? || user.deleted_at || !user.active_for_authentication?
    return unless Fcm.current.enabled?

    devices = user.device_tokens.live.to_a
    return if devices.empty?

    title, body = I18n.with_locale(user.locale) do
      values = values.transform_values do |value|
        case value
        when Proc then value.call
        when Time, ActiveSupport::TimeWithZone then I18n.l(value.in_time_zone, format: :slot)
        else value
        end
      end
      [ I18n.t("push.#{kind}.title", **values), I18n.t("push.#{kind}.body", **values) ]
    end
    devices.each { |device| PushNotificationJob.perform_later(device, title: title, body: body, path: path) }
  end
end
