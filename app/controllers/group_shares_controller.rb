# Showing one of your bookings to a group (from the groups page or the booking page), or taking it back.
class GroupSharesController < ApplicationController
  before_action :authenticate_user!

  def create
    attributes = params.require(:group_share)
    group = current_user.groups.find(attributes[:group_id])
    booking = current_user.bookings.kind_reservation.find_by!(code: attributes[:booking_code])
    share = group.share(booking, by: current_user, players: attributes[:players])
    if share.persisted?
      redirect_back_or_to groups_path, notice: t(".success", name: group.name)
    else
      redirect_back_or_to groups_path, alert: share.errors.full_messages.to_sentence
    end
  end

  # By the member who shared it, or the group's owner.
  def destroy
    share = current_user.groups.find(params[:group_id]).shares.find(params[:id])
    return redirect_back_or_to(groups_path, alert: t(".not_allowed")) unless share.removable_by?(current_user)

    share.destroy!
    redirect_back_or_to groups_path, notice: t(".success")
  end
end
