module Api
  module V1
    # The profile photo (User#avatar, TK-10): PUT /api/v1/account/avatar with a multipart "avatar" file
    # (JPG, PNG or WebP, at most 2 MB; the app shrinks it first), DELETE to remove it.
    class AvatarsController < BaseController
      rate_limit to: 10, within: 1.hour, only: :update, by: -> { current_user.id }, store: RATE_LIMIT_STORE, with: -> { rate_limited }

      def update
        file = params[:avatar]
        return render_error(:invalid, [ t("api.avatar_missing") ], status: :unprocessable_content) unless file.respond_to?(:read)

        # Nothing is stored when the photo is refused: the file is uploaded only once the record is saved.
        if current_user.update(avatar: file)
          render json: { user: ApiJson.user(current_user) }
        else
          render_error :invalid, current_user.errors.full_messages, status: :unprocessable_content
        end
      end

      def destroy
        current_user.avatar.purge if current_user.avatar.attached?
        render json: { user: ApiJson.user(current_user.reload) }
      end
    end
  end
end
