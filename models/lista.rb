# models/lista.rb
require_relative '../db'

class Lista
def self.tutti(gruppo_id)
  DB.execute("SELECT i.*, u.initials as user_initials 
              FROM items i 
              LEFT JOIN user_names u ON i.creato_da = u.user_id 
              WHERE i.gruppo_id = ? 
              ORDER BY i.comprato, i.id", [gruppo_id])
end
  def self.toggle_comprato(gruppo_id, item_id, user_id)
    DB.execute("UPDATE items SET comprato = NOT comprato WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  end

  def self.cancella(gruppo_id, item_id, user_id)
    # Implementa la logica di controllo permessi qui
    DB.execute("DELETE FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
    true
  end

  def self.cancella_tutti(gruppo_id, user_id)
    # Implementa la logica di controllo admin qui
    DB.execute("DELETE FROM items WHERE gruppo_id = ? AND comprato = 1", [gruppo_id])
    true
  end

  def self.aggiungi(gruppo_id, user_id, testo)
    articoli = testo.split(',').map(&:strip)
    articoli.each do |articolo|
      DB.execute("INSERT INTO items (gruppo_id, creato_da, nome) VALUES (?, ?, ?)", 
                [gruppo_id, user_id, articolo])
    end
  end

  def self.trova(item_id)
    DB.get_first_row("SELECT * FROM items WHERE id = ?", [item_id])
  end

   def self.ha_immagine?(item_id)
    count = DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = ?", [item_id])
    count > 0
  end

def self.get_immagine(item_id)
  # Assicurati di restituire solo se c'è un file_id valido
  row = DB.get_first_row("SELECT * FROM item_images WHERE item_id = ?", [item_id])
  row if row && row['file_id'] && !row['file_id'].empty?
end

  def self.rimuovi_immagine(item_id)
    DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id])
  end
end
