module Admin
  # Customers' ratings of the sessions they played (Review), newest first, with the average. Owner and staff.
  class ReviewsController < BaseController
    PER_PAGE = 50

    def index
      reviews = Review.joins(booking: :court).where(courts: { venue_id: venue.id })
      @average = reviews.average(:rating)&.round(1)
      @count = reviews.count
      @by_rating = reviews.group(:rating).count
      @reviews = reviews.includes(booking: :court).order(created_at: :desc).limit(PER_PAGE)
    end
  end
end
