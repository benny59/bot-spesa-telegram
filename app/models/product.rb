#require_relative '../db'

class Product
  DB_FILE = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'spesa.db'))

  def self.save_nutrition_for(barcode_or_id, nutriments)
    db = '../../spesa.db'
    if nutriments.nil? || nutriments.empty?
      warn "No nutriments to save"
      return
    end

    # If barcode_or_id looks numeric, try to find product by barcode first
    if barcode_or_id.to_s =~ /^\d+$/
      row = db.get_first_row("SELECT id FROM products WHERE barcode = ?", barcode_or_id)
      if row
        id = row[0]
        update_sql = <<-SQL
          UPDATE products SET
            energy_kcal = ?,
            fat_g = ?,
            saturated_fat_g = ?,
            carbohydrates_g = ?,
            sugars_g = ?,
            proteins_g = ?,
            salt_g = ?,
            fiber_g = ?
          WHERE id = ?
        SQL
        db.execute(update_sql, [
          nutriments[:energy_kcal],
          nutriments[:fat_g],
          nutriments[:saturated_fat_g],
          nutriments[:carbohydrates_g],
          nutriments[:sugars_g],
          nutriments[:proteins_g],
          nutriments[:salt_g],
          nutriments[:fiber_g],
          id
        ])
        return id
      end
    end

    # fallback: try update by name (best-effort) or insert new product
    if barcode_or_id.is_a?(String)
      row = db.get_first_row("SELECT id FROM products WHERE name = ?", barcode_or_id)
      if row
        id = row[0]
        db.execute("UPDATE products SET energy_kcal=?, fat_g=?, saturated_fat_g=?, carbohydrates_g=?, sugars_g=?, proteins_g=?, salt_g=?, fiber_g=? WHERE id=?",
                   nutriments.values_at(:energy_kcal, :fat_g, :saturated_fat_g, :carbohydrates_g, :sugars_g, :proteins_g, :salt_g, :fiber_g, id))
        return id
      end
    end

    # insert a minimal product record if no matching product exists
    insert_sql = <<-SQL
      INSERT INTO products (barcode, name, energy_kcal, fat_g, saturated_fat_g, carbohydrates_g, sugars_g, proteins_g, salt_g, fiber_g)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    db.execute(insert_sql, [
      nutrit = nil,
      barcode_or_id.is_a?(String) && barcode_or_id =~ /^\d+$/ ? barcode_or_id : nil,
      nutriments[:name],
      nutriments[:energy_kcal],
      nutriments[:fat_g],
      nutriments[:saturated_fat_g],
      nutriments[:carbohydrates_g],
      nutriments[:sugars_g],
      nutriments[:proteins_g],
      nutriments[:salt_g],
      nutriments[:fiber_g]
    ])
    db.last_insert_row_id
  end
  
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
    create_table!  # CHIAMA IL METODO APPENA AGGIUNTO
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
    create_table!  # CHIAMA IL METODO APPENA AGGIUNTO
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
    create_table!  # CHIAMA IL METODO APPENA AGGIUNTO
    db = SQLite3::Database.new(DB_FILE)
    row = db.get_first_row("SELECT id, item_id, characteristics, created_at FROM products WHERE barcode = ? ORDER BY id DESC LIMIT 1", barcode)
    db.close
    return nil unless row
    { id: row[0], item_id: row[1], characteristics: JSON.parse(row[2]), created_at: row[3] }
  rescue => e
    warn "Product.find_latest_by_barcode error: #{e.class}: #{e.message}"
    nil
  end

  # METODO ALTERNATivo per compatibilità
  def self.save_product(barcode, characteristics, chat_id)
    save_for_item(item_id: chat_id, barcode: barcode, characteristics: characteristics)
  end
end


