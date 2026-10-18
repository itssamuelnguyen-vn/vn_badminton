class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    # One per signed-in app (ApiToken). Only a digest is stored: the token itself is shown once, to the app.
    create_table :api_tokens do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :token_digest, null: false, index: { unique: true }
      t.string :device_name
      t.datetime :last_used_at, precision: 0, null: false
      t.timestamps precision: 0
    end
  end
end
