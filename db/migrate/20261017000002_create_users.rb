# Columns compatible with Devise (database_authenticatable, recoverable, rememberable).
# role:
#   customer : books courts
#   admin    : venue owner with full management rights
# To add employees later, add 'staff' to the users_role_valid constraint in a small migration.
class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.citext   :email,              null: false
      t.string   :encrypted_password, null: false, default: ""
      t.string   :reset_password_token
      t.datetime :reset_password_sent_at
      t.datetime :remember_created_at

      t.string :full_name, null: false
      t.string :phone # stored as E.164: +84xxxxxxxxx
      t.string :role, null: false, default: "customer"

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :phone, unique: true, where: "phone IS NOT NULL"
    add_index :users, :reset_password_token, unique: true

    add_check_constraint :users, "role IN ('customer', 'admin')", name: "users_role_valid"
    add_check_constraint :users, "length(btrim(full_name)) BETWEEN 1 AND 100", name: "users_full_name_length"
    add_check_constraint :users, %q(email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'), name: "users_email_format"
    add_check_constraint :users, %q(phone ~ '^\+84[0-9]{9}$'), name: "users_phone_format"
  end
end
