# "Tell me when a court frees up" (WaitlistEntry, TI-04): added from the schedule's form, removed from
# "Lượt đặt của tôi".
class WaitlistEntriesController < ApplicationController
  before_action :authenticate_user!

  def create
    entry = current_user.waitlist_entries.new(params.require(:waitlist_entry).permit(:starts_at, :ends_at))
    date = entry.starts_at&.in_time_zone(Venue.main.zone)&.to_date&.iso8601
    if entry.save
      redirect_to root_path(date: date), notice: t(".success", time: "#{l(entry.starts_at.to_date, format: :day_month_year)} #{helpers.time_range(entry.starts_at, entry.ends_at)}")
    else
      redirect_to root_path(date: date), alert: entry.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.waitlist_entries.find(params[:id]).destroy!
    redirect_to bookings_path, notice: t(".success")
  end
end
