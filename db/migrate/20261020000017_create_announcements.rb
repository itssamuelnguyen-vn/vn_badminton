class CreateAnnouncements < ActiveRecord::Migration[8.1]
  def change
    # News the owner posts on the booking page and in the app (holiday closing, off-peak offer, tournament).
    create_table :announcements do |t|
      t.references :venue, null: false, foreign_key: true
      t.string :title, null: false
      t.string :title_en
      t.text :body
      t.text :body_en
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.string :tone, null: false, default: "info"
      t.timestamps precision: 0
    end
    add_check_constraint :announcements, "ends_on >= starts_on", name: "announcements_date_range_valid"
    add_check_constraint :announcements, "tone IN ('info', 'offer', 'warning')", name: "announcements_tone_valid"
  end
end
