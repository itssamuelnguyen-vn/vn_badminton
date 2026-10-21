module Admin
  # The owner's news on the booking page and in the app (Announcement), shown between two dates. Owner only.
  class AnnouncementsController < BaseController
    before_action :require_owner
    before_action :set_announcement, only: %i[edit update destroy]

    def index
      @announcements = venue.announcements.order(ends_on: :desc, starts_on: :desc)
      @today = venue.today
    end

    def new
      @announcement = venue.announcements.new(starts_on: venue.today, ends_on: venue.today + 7)
    end

    def create
      @announcement = venue.announcements.new(announcement_params)
      if @announcement.save
        redirect_to admin_announcements_path, notice: t(".success")
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @announcement.update(announcement_params)
        redirect_to admin_announcements_path, notice: t(".success")
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @announcement.destroy!
      redirect_to admin_announcements_path, notice: t(".success")
    end

    # The announcements ticked on the list (ids[]), deleted together.
    def destroy_many
      count = venue.announcements.where(id: Array(params[:ids])).destroy_all.size
      redirect_to admin_announcements_path, notice: t(".success", count: count)
    end

    private

    def set_announcement
      @announcement = venue.announcements.find(params[:id])
    end

    def announcement_params
      params.require(:announcement).permit(:title, :title_en, :body, :body_en, :starts_on, :ends_on, :tone)
    end
  end
end
