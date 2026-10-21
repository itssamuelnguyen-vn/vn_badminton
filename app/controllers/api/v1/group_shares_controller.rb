module Api
  module V1
    # Showing one of your bookings to a group ({ booking_code, players }), or taking it back.
    class GroupSharesController < BaseController
      def create
        group = current_user.groups.find(params[:group_id])
        booking = current_user.bookings.kind_reservation.find_by!(code: params.require(:booking_code))
        share = group.share(booking, by: current_user, players: params[:players])
        if share.persisted?
          render json: ApiJson.group(group.reload, current_user), status: :created
        else
          render_error :invalid, share.errors.full_messages, status: :unprocessable_content
        end
      end

      # By the member who shared it, or the group's owner.
      def destroy
        group = current_user.groups.find(params[:group_id])
        share = group.shares.find(params[:id])
        return render_error(:not_allowed, [], status: :forbidden) unless share.removable_by?(current_user)

        share.destroy!
        head :no_content
      end
    end
  end
end
