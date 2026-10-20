# Short notices to a customer about the app's extra features: a court that freed up (WaitlistJob) and the
# venue's answer to a weekly booking request (SeriesRequest).
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
end
