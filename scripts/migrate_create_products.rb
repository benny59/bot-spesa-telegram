# Run: ruby scripts/migrate_create_products.rb
require_relative '../db'

db = DB.db

db.execute <<-SQL
CREATE TABLE IF NOT EXISTS products (
  id INTEGER PRIMARY KEY,
  barcode TEXT,
  name TEXT,
  brand TEXT,
  image_url TEXT,
  raw_off_json TEXT,
  energy_kcal REAL,
  fat_g REAL,
  saturated_fat_g REAL,
  carbohydrates_g REAL,
  sugars_g REAL,
  proteins_g REAL,
  salt_g REAL,
  fiber_g REAL,
  last_checked_at TEXT
);
SQL

# unique index on barcode when present (SQLite supports partial indexes from 3.8.0)
begin
  db.execute <<-SQL
    CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode) WHERE barcode IS NOT NULL;
  SQL
rescue SQLite3::SQLException
  # Older SQLite versions may not support WHERE clause in index; create non-partial unique index safely.
  db.execute "CREATE UNIQUE INDEX IF NOT EXISTS idx_products_barcode_all ON products(barcode);"
end

puts "products table and indexes ensured."