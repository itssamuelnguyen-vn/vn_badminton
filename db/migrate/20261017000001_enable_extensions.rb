# citext     : case-insensitive email comparison inside the DB
# btree_gist : allows the "=" operator on court_id inside a GiST exclusion constraint
class EnableExtensions < ActiveRecord::Migration[8.1]
  def change
    enable_extension "citext"
    enable_extension "btree_gist"
  end
end
