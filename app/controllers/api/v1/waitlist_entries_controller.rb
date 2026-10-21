module Api
  module V1
    # "Tell me when it frees up" (WaitlistEntry): the customer's waits, adding one ({ starts_at, ends_at }) and removing one.
    class WaitlistEntriesController < BaseController
      def index
        render json: { entries: current_user.waitlist_entries.waiting.order(:starts_at).map { |entry| ApiJson.waitlist_entry(entry) } }
      end

      def create
        entry = current_user.waitlist_entries.new(params.permit(:starts_at, :ends_at))
        if entry.save
          render json: ApiJson.waitlist_entry(entry), status: :created
        else
          render_error :invalid, entry.errors.full_messages, status: :unprocessable_content
        end
      end

      def destroy
        current_user.waitlist_entries.find(params[:id]).destroy!
        head :no_content
      end
    end
  end
end
