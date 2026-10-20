module Api
  module V1
    # The signed-in customer's account: details, the verification email, the data export (JSON) and deletion
    # (Accounts::Deletion), each sensitive action asked with the password like on the web.
    class AccountsController < BaseController
      rate_limit to: 5, within: 1.hour, only: %i[export destroy resend_verification], store: RATE_LIMIT_STORE, with: -> { rate_limited }

      def show
        deletion = Accounts::Deletion.new(current_user)
        render json: { user: ApiJson.user(current_user), can_delete: deletion.allowed?,
                       bookings_to_play: deletion.pending_bookings.map { |booking| ApiJson.booking(booking) },
                       deleted_after: deletion.finishes_at&.iso8601 }
      end

      def update
        if current_user.update(params.permit(:full_name, :phone, :locale, :birth_year, :gender, :skill_level))
          render json: { user: ApiJson.user(current_user) }
        else
          render_error :invalid, current_user.errors.full_messages, status: :unprocessable_content
        end
      end

      def resend_verification
        current_user.send_confirmation_instructions unless current_user.confirmed?
        head :no_content
      end

      def export
        return wrong_password unless current_user.valid_password?(params[:password].to_s)

        render json: Accounts::DataExport.new(current_user).as_json
      end

      def destroy
        deletion = Accounts::Deletion.new(current_user)
        return render_error(:not_allowed, [ t("users.registrations.destroy.not_allowed") ], status: :forbidden) unless deletion.allowed?
        return wrong_password unless current_user.valid_password?(params[:password].to_s)

        finishes_at = deletion.finishes_at
        deletion.request!(by: current_user)
        render json: { deleted_after: finishes_at&.iso8601 }
      end

      private

      def wrong_password
        render_error :wrong_password, [ t("users.registrations.destroy.wrong_password") ], status: :forbidden
      end
    end
  end
end
