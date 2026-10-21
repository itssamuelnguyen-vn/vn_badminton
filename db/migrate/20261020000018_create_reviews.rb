class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    # A customer's rating of a session they played (1-5 stars and a comment), seen only by the owner and staff.
    create_table :reviews do |t|
      t.references :booking, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :rating, limit: 2, null: false
      t.text :comment
      t.timestamps precision: 0
    end
    add_check_constraint :reviews, "rating BETWEEN 1 AND 5", name: "reviews_rating_valid"
  end
end
