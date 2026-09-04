# models/lista.rb
require_relative "../db"

class Lista
  CONFIG_PREFERITI_NOME = '__botspesa_favorites_backup__ & config'.freeze

  def self.tutti(gruppo_id, topic_id)
    rows = DB.execute(
      "SELECT i.*, u.initials AS user_initials, buyer.initials AS buyer_initials, c.nome AS categoria_nome
     FROM items i
     LEFT JOIN user_names u ON i.creato_da = u.user_id
    LEFT JOIN user_names buyer ON CAST(i.comprato AS INTEGER) = buyer.user_id
    LEFT JOIN categorie c ON i.categoria_id = c.id
     WHERE i.gruppo_id = ?
       AND i.topic_id = ?
       AND i.nome != ?
     ORDER BY #{DataManager.item_state_order_sql("i")}, CASE WHEN c.nome IS NULL THEN 1 ELSE 0 END ASC, c.nome ASC, i.id DESC",
      [gruppo_id, topic_id, CONFIG_PREFERITI_NOME]
    )
    DataManager.ordina_items_per_categoria(rows)
  end

  def self.personale(user_id)
    rows = DB.execute(
      "SELECT i.*, u.initials AS user_initials, buyer.initials AS buyer_initials, c.nome AS categoria_nome
     FROM items i
     LEFT JOIN user_names u ON i.creato_da = u.user_id
    LEFT JOIN user_names buyer ON CAST(i.comprato AS INTEGER) = buyer.user_id
    LEFT JOIN categorie c ON i.categoria_id = c.id
    WHERE i.gruppo_id = 0 AND i.creato_da = ? AND i.nome != ?
     ORDER BY #{DataManager.item_state_order_sql("i")}, CASE WHEN c.nome IS NULL THEN 1 ELSE 0 END ASC, c.nome ASC, i.id DESC",
     [user_id, CONFIG_PREFERITI_NOME]
    )
    DataManager.ordina_items_per_categoria(rows)
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
    # Soft delete: l'item resta nel DB per undo ma viene nascosto dalla lista attiva.
    DB.execute("UPDATE items SET deleted = 1 WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    DB.changes > 0
  end

  def self.cancella_tutti(gruppo_id, user_id)
    # Dopo il soft-delete, la scopetta definitiva deve ignorare gli item nascosti.
    DB.execute("DELETE FROM items WHERE gruppo_id = ? AND deleted = 0 AND comprato IS NOT NULL AND TRIM(comprato) <> ''", [gruppo_id])
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

  def self.aggiorna_categoria(item_id, categoria_id)
    categoria_id = categoria_id.to_i if categoria_id
    categoria_id = nil if categoria_id && categoria_id <= 0
    DB.execute("UPDATE items SET categoria_id = ? WHERE id = ?", [categoria_id, item_id])
    DB.changes > 0
  end

  def self.sposta_topic(item_id, gruppo_id, topic_id)
    DB.execute(
      "UPDATE items SET gruppo_id = ?, topic_id = ? WHERE id = ?",
      [gruppo_id, topic_id, item_id]
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
