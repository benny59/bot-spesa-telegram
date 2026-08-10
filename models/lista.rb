# models/lista.rb
require_relative "../db"

class Lista
  def self.tutti(gruppo_id, topic_id)
    DB.execute(
      "SELECT i.*, u.initials AS user_initials, buyer.initials AS buyer_initials
     FROM items i
     LEFT JOIN user_names u ON i.creato_da = u.user_id
    LEFT JOIN user_names buyer ON CAST(i.comprato AS INTEGER) = buyer.user_id
     WHERE i.gruppo_id = ?
       AND i.topic_id = ?
     ORDER BY i.comprato, i.id",
      [gruppo_id, topic_id]
    )
  end

  def self.personale(user_id)
    DB.execute(
      "SELECT i.*, u.initials AS user_initials, buyer.initials AS buyer_initials
     FROM items i
     LEFT JOIN user_names u ON i.creato_da = u.user_id
    LEFT JOIN user_names buyer ON CAST(i.comprato AS INTEGER) = buyer.user_id
     WHERE i.gruppo_id = 0 AND i.creato_da = ?
     ORDER BY i.comprato, i.id",
      [user_id]
    )
  end
  # models/lista.rb
  def self.toggle_comprato(gruppo_id, item_id, user_id)
    item = DB.get_first_row("SELECT comprato FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    return nil unless item

    current = item["comprato"]

    if current.nil? || current.to_s.strip == "" || current.to_s == "0"
      DataManager.spunta_articolo(item_id, user_id)
    else
      DataManager.despunta_articolo(item_id)
      puts "🔁 Item #{item_id} rimesso da comprare (prima: #{current})"
      ""
    end
  end

  def self.cancella(gruppo_id, item_id, user_id)
    # Implementa la logica di controllo permessi qui
    DB.execute("DELETE FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    true
  end

  def self.cancella_tutti(gruppo_id, user_id)
    # Implementa la logica di controllo admin qui
    DB.execute("DELETE FROM items WHERE gruppo_id = ? AND comprato IS NOT NULL AND TRIM(comprato) <> ''", [gruppo_id])
    true
  end

  def self.aggiungi(gruppo_id, user_id, testo, topic_id = 0)
    articoli = testo.split(",").map(&:strip)
    articoli.each do |articolo|
      sql = "INSERT INTO items (gruppo_id, creato_da, nome, creato_il, topic_id) VALUES (?, ?, ?, datetime('now'), ?)"
      params = [gruppo_id, user_id, articolo, topic_id]

      puts "DEBUG [Lista:Aggiungi] SQL: #{sql} | PARAMS: #{params.inspect}"
      begin
        DB.execute(sql, params)
        puts "✅ [Lista:Aggiungi] Articolo '#{articolo}' salvato"
      rescue => e
        puts "❌ [Lista:Aggiungi] CRASH: #{e.message}"
        raise e
      end
    end
  end

  def self.aggiungi_immagine(item_id, file_id, file_unique_id = nil)
    DB.execute(
      "INSERT OR REPLACE INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
      [item_id, file_id, file_unique_id]
    )
  end

  def self.trova(item_id)
    DB.get_first_row("SELECT * FROM items WHERE id = ?", [item_id])
  end

  def self.modifica_nome(item_id, nome)
    DB.execute("UPDATE items SET nome = ? WHERE id = ?", [nome, item_id])
    DB.changes > 0
  end

  def self.sposta_topic(item_id, gruppo_id, topic_id)
    DB.execute(
      "UPDATE items SET topic_id = ? WHERE id = ? AND gruppo_id = ?",
      [topic_id, item_id, gruppo_id]
    )
    DB.changes > 0
  end

  def self.ha_immagine?(item_id)
    count = DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = ?", [item_id])
    count > 0
  end

  def self.get_immagine(item_id)
    # Prendi la prima riga (dovrebbe essere l'unica dopo le nostre modifiche)
    row = DB.get_first_row("SELECT * FROM item_images WHERE item_id = ?", [item_id])
    row if row && row["file_id"] && !row["file_id"].empty?
  end

  def self.rimuovi_immagine(item_id)
    immagini = DB.execute(
      "SELECT file_id, file_unique_id FROM item_images WHERE item_id = ?",
      [item_id]
    )
    DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id])
    immagini
  end
end
