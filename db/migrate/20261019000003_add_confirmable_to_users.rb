# Devise :confirmable. Accounts created before email verification existed count as verified.
class AddConfirmableToUsers < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.string :confirmation_token
      t.datetime :confirmed_at, precision: 0
      t.datetime :confirmation_sent_at, precision: 0
      t.string :unconfirmed_email # the new address while an email change waits for verification
      t.index :confirmation_token, unique: true
    end

    up_only { execute "UPDATE users SET confirmed_at = created_at" }
  end
end
