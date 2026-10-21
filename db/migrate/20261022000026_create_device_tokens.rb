class CreateDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    # The phones that get push notifications (Firebase Cloud Messaging), one row per FCM registration token.
    # A token belongs to the app's sign-in it was sent with (api_tokens): signing out, a new password or the
    # account's deletion removes the sign-in, and the phone stops getting notifications with it.
    create_table :device_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.references :api_token, null: false, foreign_key: { on_delete: :cascade }
      t.string :token, null: false, index: { unique: true }
      t.string :platform, null: false, default: "android"
      t.string :app_version
      t.datetime :last_seen_at, precision: 0, null: false
      t.timestamps precision: 0
    end

    # Signing in with Google (Api::V1): the account's Google ID (the ID token's "sub").
    add_column :users, :google_uid, :string
    add_index :users, :google_uid, unique: true, where: "google_uid IS NOT NULL"
  end
end
