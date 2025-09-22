require_relative '../db'

class Product
  def self.save_nutrition_for(barcode_or_id, nutriments)
    db = DB.db
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
end