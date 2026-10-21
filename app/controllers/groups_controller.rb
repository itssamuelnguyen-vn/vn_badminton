# The customer's groups (NH-01..03): members, the bookings shared with each group still to play, and a form to
# share one of their own. Create a group, join one by its code, leave one, or delete one you own.
class GroupsController < ApplicationController
  before_action :authenticate_user!

  def index
    @groups = current_user.groups.includes(:owner, members: [], shares: [ :shared_by, { booking: :court } ]).order(:name)
    @shareable = current_user.bookings.kind_reservation.where(status: BookingsController::UPCOMING_STATUSES)
                             .where(ends_at: Time.current..).includes(:court).order(:starts_at)
  end

  def create
    group = Group.create_for(current_user, params.require(:group).fetch(:name, ""))
    if group.persisted?
      redirect_to groups_path(anchor: helpers.dom_id(group)), notice: t(".success", code: group.invite_code)
    else
      redirect_to groups_path, alert: group.errors.full_messages.to_sentence
    end
  end

  def join
    group = Group.find_code(params[:code])
    return redirect_to(groups_path, alert: t(".wrong_code")) unless group

    if group.join(current_user)
      redirect_to groups_path(anchor: helpers.dom_id(group)), notice: t(".success", name: group.name)
    else
      redirect_to groups_path, alert: group.errors.full_messages.to_sentence
    end
  end

  def leave
    current_user.groups.find(params[:id]).remove(current_user)
    redirect_to groups_path, notice: t(".success")
  end

  def destroy
    current_user.groups.where(owner: current_user).find(params[:id]).destroy!
    redirect_to groups_path, notice: t(".success")
  end
end
