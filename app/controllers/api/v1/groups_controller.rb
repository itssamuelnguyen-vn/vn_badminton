module Api
  module V1
    # The customer's groups (Group): members' names and the bookings shared with each group still to play.
    # Create one ({ name }), join one ({ code }), leave one, or delete one you own.
    class GroupsController < BaseController
      def index
        groups = current_user.groups.includes(:owner, members: [], shares: [ :shared_by, { booking: :court } ]).order(:name)
        render json: { groups: groups.map { |group| ApiJson.group(group, current_user) } }
      end

      def create
        group = Group.create_for(current_user, params.require(:name))
        if group.persisted?
          render json: ApiJson.group(group, current_user), status: :created
        else
          render_error :invalid, group.errors.full_messages, status: :unprocessable_content
        end
      end

      def join
        group = Group.find_code(params.require(:code))
        return render_error(:not_found, [ t("api.groups.wrong_code") ], status: :not_found) unless group

        if group.join(current_user)
          render json: ApiJson.group(group.reload, current_user)
        else
          render_error :invalid, group.errors.full_messages, status: :unprocessable_content
        end
      end

      def leave
        current_user.groups.find(params[:id]).remove(current_user)
        head :no_content
      end

      def destroy
        current_user.groups.where(owner: current_user).find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
