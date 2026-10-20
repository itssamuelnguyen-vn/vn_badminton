module Accounts
  # Everything the app keeps about a customer's account, as JSON for them to download ("Tải dữ liệu của tôi"):
  # the account, every booking with its history, the payments and the transfers matched to them.
  # Staff are named "venue" in the history (their names are not the customer's data). The venue's private
  # note on the customer is not included.
  #
  #   Accounts::DataExport.new(user).to_json
  class DataExport
    def initialize(user, now: Time.current)
      @user = user
      @now = now
    end

    def to_json(*)
      JSON.pretty_generate(as_json)
    end

    def as_json(*)
      {
        exported_at: @now.iso8601,
        account: account,
        bookings: bookings,
        payments: payments,
        series_requests: series_requests,
        reviews: reviews,
        waitlist: waitlist
      }
    end

    def filename
      "vn-badminton-du-lieu-cua-toi-#{@now.to_date.iso8601}.json"
    end

    private

    def account
      {
        full_name: @user.full_name, email: @user.email, phone: @user.phone, locale: @user.locale,
        created_at: @user.created_at&.iso8601, email_confirmed_at: @user.confirmed_at&.iso8601,
        privacy_accepted_at: @user.privacy_accepted_at&.iso8601, booking_locked_until: @user.booking_locked_until&.iso8601,
        birth_year: @user.birth_year, gender: @user.gender, skill_level: @user.skill_level,
        avatar: (@user.avatar.filename.to_s if @user.avatar.attached?)
      }
    end

    def bookings
      @user.bookings.includes(:court, :items, events: :actor).order(:starts_at).map do |booking|
        {
          code: booking.code, court: booking.court.display_name, starts_at: booking.starts_at.iso8601, ends_at: booking.ends_at.iso8601,
          status: booking.status, source: booking.source, customer_name: booking.customer_name, customer_phone: booking.customer_phone,
          amount_vnd: booking.total_amount_vnd, payment_status: booking.payment_status, paid_at: booking.paid_at&.iso8601,
          checked_in_at: booking.checked_in_at&.iso8601, cancelled_at: booking.cancelled_at&.iso8601,
          cancellation_reason: booking.cancellation_reason, refund_vnd: booking.refund_vnd, refunded_at: booking.refunded_at&.iso8601,
          note: booking.note, created_at: booking.created_at.iso8601,
          items: booking.items.map { |item| { name: item.name, quantity: item.quantity, unit_price_vnd: item.unit_price_vnd } },
          history: booking.events.map { |event| { at: event.created_at.iso8601, action: event.action, by: by(event), details: event.details } }
        }
      end
    end

    def payments
      Payment.where(user: @user).includes(:transfers).order(:created_at).map do |payment|
        {
          code: payment.code, purpose: payment.purpose, amount_vnd: payment.amount_vnd, status: payment.status,
          created_at: payment.created_at.iso8601, expires_at: payment.expires_at&.iso8601, paid_at: payment.paid_at&.iso8601,
          transfers: payment.transfers.money_in.order(:id).map do |transfer|
            { amount_vnd: transfer.amount_vnd, at: transfer.transacted_at&.iso8601, bank: transfer.gateway, content: transfer.content,
              reference: transfer.reference_code }
          end
        }
      end
    end

    def series_requests
      @user.series_requests.order(:created_at).map do |request|
        { courts: request.courts.map(&:display_name), days_of_week: request.days_of_week, start_minute: request.start_minute,
          end_minute: request.end_minute, starts_on: request.starts_on.iso8601, ends_on: request.ends_on.iso8601, note: request.note,
          status: request.status, decline_reason: request.decline_reason, created_at: request.created_at.iso8601 }
      end
    end

    def reviews
      @user.reviews.includes(:booking).order(:created_at).map do |review|
        { booking: review.booking.code, rating: review.rating, comment: review.comment, created_at: review.created_at.iso8601 }
      end
    end

    def waitlist
      @user.waitlist_entries.order(:starts_at).map do |entry|
        { starts_at: entry.starts_at.iso8601, ends_at: entry.ends_at.iso8601, notified_at: entry.notified_at&.iso8601 }
      end
    end

    def by(event)
      if event.actor.nil? then "system"
      elsif event.actor == @user then "you"
      else "venue"
      end
    end
  end
end
