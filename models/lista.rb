# models/lista.rb
require_relative "../db"

class Lista
  def self.tutti(gruppo_id)
    DB.execute("SELECT i.*, u.initials as user_initials 
              FROM items i 
              LEFT JOIN user_names u ON i.creato_da = u.user_id 
              WHERE i.gruppo_id = ? 
              ORDER BY i.comprato, i.id", [gruppo_id])
  end
  # models/lista.rb
  def self.toggle_comprato(gruppo_id, item_id, user_id)
    item = DB.get_first_row("SELECT comprato FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    return nil unless item

    current = item["comprato"]

    # Se il campo è vuoto / nil / '0' => segna come comprato con le iniziali dell'utente
    if current.nil? || current.to_s.strip == "" || current.to_s == "0"
      # prova a recuperare le iniziali dall'utente
      initials = DB.get_first_value("SELECT initials FROM user_names WHERE user_id = ?", [user_id])
      if initials.nil? || initials.to_s.strip == ""
        # se non esistono, costruiscile da first_name / last_name
        fn = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || ""
        ln = DB.get_first_value("SELECT last_name FROM user_names WHERE user_id = ?", [user_id]) || ""
        initials = if fn.to_s.strip != "" && ln.to_s.strip != ""
            "#{fn[0]}#{ln[0]}".upcase
          elsif fn.to_s.strip != ""
            fn[0].upcase
          else
            "U"
          end
        # salva le iniziali per il futuro (non rompe se la tabella user_names non esiste)
        begin
          DB.execute("INSERT OR REPLACE INTO user_names (user_id, first_name, last_name, initials) VALUES (?, ?, ?, ?)",
                     [user_id, fn, ln, initials])
        rescue => e
          puts "⚠️ Impossibile scrivere user_names: #{e.message}"
        end
      end

      DB.execute("UPDATE items SET comprato = ? WHERE id = ? AND gruppo_id = ?", [initials, item_id, gruppo_id])
      puts "🔁 Item #{item_id} marcato come comprato da #{initials}"
      initials
    else
      # Se contiene già qualcosa (la sigla) => togli il comprato (riporta a non comprato)
      DB.execute("UPDATE items SET comprato = '' WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
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

  def self.aggiungi(gruppo_id, user_id, testo)
    articoli = testo.split(",").map(&:strip)
    articoli.each do |articolo|
      DB.execute("INSERT INTO items (gruppo_id, creato_da, nome) VALUES (?, ?, ?)",
                 [gruppo_id, user_id, articolo])
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
    DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id])
  end
end
