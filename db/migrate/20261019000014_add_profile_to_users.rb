class AddProfileToUsers < ActiveRecord::Migration[8.1]
  def change
    # Optional profile shown in the app (TK-10). Nothing else about the person is asked: only what the venue uses.
    change_table :users, bulk: true do |t|
      t.integer :birth_year
      t.string :gender
      t.string :skill_level
      t.check_constraint "gender IN ('male', 'female', 'other')", name: "users_gender_valid"
      t.check_constraint "skill_level IN ('beginner', 'intermediate', 'advanced', 'expert')", name: "users_skill_level_valid"
      t.check_constraint "birth_year BETWEEN 1900 AND 2100", name: "users_birth_year_range"
    end
  end
end
