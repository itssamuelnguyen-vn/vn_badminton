# Courts are now named with a bare number ("3") and shown as "Sân 3" / "Court 3" by Court#display_name.
class RenameCourtsToNumbers < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE courts SET name = substring(name from '^Sân (\\d+)$') WHERE name ~ '^Sân \\d+$'"
  end

  def down
    execute "UPDATE courts SET name = 'Sân ' || name WHERE name ~ '^\\d+$'"
  end
end
