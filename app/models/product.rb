require 'sqlite3'
require 'json'
require 'time'
require 'fileutils'

class Product
  # ensure DB file matches your app. By default use spesa.db at repo root.
  DB_FILE = File.expand_path(File.join(__dir__, '..', '..', 'spesa.db'))

  def self.create_table!
    FileUtils.mkdir_p(File.dirname(DB_FILE))
    db = SQLite3::Database.new(DB_FILE)
    db.execute <<-SQL
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY,
        item_id INTEGER,
        barcode TEXT,
        characteristics TEXT,
        created_at TEXT
      );
    SQL
    db.execute "CREATE INDEX IF NOT EXISTS idx_products_item_id ON products(item_id);" rescue nil
    db.execute "CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);" rescue nil
    db.close
  end

  def self.save_for_item(item_id:, barcode:, characteristics:)
    create_table!
    db = SQLite3::Database.new(DB_FILE)
    db.execute(
      "INSERT INTO products (item_id, barcode, characteristics, created_at) VALUES (?, ?, ?, ?)",
      [item_id, barcode, characteristics.to_json, Time.now.iso8601]
    )
    db.close
    true
  rescue => e
    warn "Product.save_for_item error: #{e.class}: #{e.message}"
    false
  end

  def self.find_by_item(item_id)
    create_table!
    db = SQLite3::Database.new(DB_FILE)
    row = db.get_first_row("SELECT id, barcode, characteristics, created_at FROM products WHERE item_id = ? ORDER BY id DESC LIMIT 1", item_id)
    db.close
    return nil unless row
    { id: row[0], barcode: row[1], characteristics: JSON.parse(row[2]), created_at: row[3] }
  rescue => e
    warn "Product.find_by_item error: #{e.class}: #{e.message}"
    nil
  end

  def self.find_latest_by_barcode(barcode)
    create_table!
    db = SQLite3::Database.new(DB_FILE)
    row = db.get_first_row("SELECT id, item_id, characteristics, created_at FROM products WHERE barcode = ? ORDER BY id DESC LIMIT 1", barcode)
    db.close
    return nil unless row
    { id: row[0], item_id: row[1], characteristics: JSON.parse(row[2]), created_at: row[3] }
  rescue => e
    warn "Product.find_latest_by_barcode error: #{e.class}: #{e.message}"
    nil
  end
end