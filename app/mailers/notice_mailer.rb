# Short notices to a customer about the app's extra features: a court that freed up (WaitlistJob), the
# venue's answer to a weekly booking request (SeriesRequest) and a weekly booking moved by the venue.
class NoticeMailer < ApplicationMailer
  helper :bookings

  def slot_freed
    @entry = params[:entry]
    user = @entry.user
    @venue = Venue.main

    I18n.with_locale(user.locale) do
      mail to: user.email, subject: t(".subject", time: l(@entry.starts_at.in_time_zone(@venue.zone), format: :slot))
    end
  end

  def series_request_decided
    @series_request = params[:series_request]
    user = @series_request.user

    I18n.with_locale(user.locale) do
      mail to: user.email, subject: t(".subject_#{@series_request.status}")
    end
  end

  # The venue cancelled an open play session the customer had places in (paid ones are refunded).
  def play_session_cancelled
    @ticket = params[:ticket]
    @session = @ticket.play_session
    user = @ticket.user
    return if user.deleted_at

    I18n.with_locale(user.locale) do
      mail to: user.email, subject: t(".subject", title: @session.display_title, time: l(@session.starts_at.in_time_zone(@session.venue.zone), format: :slot))
    end
  end

  # The venue cancelled a tournament the customer entered (a paid fee is refunded).
  def tournament_cancelled
    @entry = params[:entry]
    @tournament = @entry.tournament
    user = @entry.user
    return if user.deleted_at

    I18n.with_locale(user.locale) do
      mail to: user.email, subject: t(".subject", title: @tournament.display_title,
                                                  time: l(@tournament.starts_at.in_time_zone(@tournament.venue.zone), format: :slot))
    end
  end

  # The venue moved the customer's weekly booking (Series::Move): each session moved, old and new slot.
  def series_moved
    @series = params[:series]
    @sessions = params[:sessions]
    @kept = params[:kept]
    user = @series.user

    I18n.with_locale(user.locale) do
      mail to: user.email, subject: t(".subject", count: @sessions.size)
    end
  end
end
