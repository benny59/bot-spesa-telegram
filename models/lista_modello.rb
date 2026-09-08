require_relative "../db"
require "json"

class ListaModello
  def self.crea(gruppo_id, topic_id, user_id, nome, items_raw_array)
    nome = nome.to_s.strip
    items = Array(items_raw_array).map { |item| item.to_s.strip }.reject(&:empty?)

    if nome.empty?
      return { status: :errore, messaggio: "Nome modello non valido." }
    end

    if items.empty?
      return { status: :errore, messaggio: "Nessun articolo nel modello." }
    end

    items_json = JSON.generate(items)

    begin
      DB.execute(
        "INSERT INTO liste_modello (gruppo_id, topic_id, nome, items_raw, creato_da, aggiornato_il) VALUES (?, ?, ?, ?, ?, datetime('now'))",
        [gruppo_id.to_i, topic_id.to_i, nome, items_json, user_id.to_i]
      )
      { status: :creato, id: DB.last_insert_row_id }
    rescue SQLite3::ConstraintException
      { status: :duplicato, messaggio: "Esiste già un modello con questo nome in questo contesto." }
    rescue => e
      puts "❌ [LISTA_MODELLO] Errore salvataggio: #{e.message}"
      { status: :errore, messaggio: e.message }
    end
  end

  def self.disponibili(gruppo_id, topic_id, user_id)
    gruppo_id = gruppo_id.to_i
    topic_id = topic_id.to_i
    user_id = user_id.to_i

    DB.execute(
      "SELECT * FROM liste_modello WHERE (gruppo_id = ? AND topic_id = ?) OR (gruppo_id = 0 AND creato_da = ?) ORDER BY nome ASC",
      [gruppo_id, topic_id, user_id]
    )
  end

  def self.trova(modello_id)
    DB.get_first_row("SELECT * FROM liste_modello WHERE id = ? LIMIT 1", [modello_id.to_i])
  end

  def self.elimina(modello_id, user_id)
    modello_id = modello_id.to_i
    user_id = user_id.to_i
    return false if modello_id <= 0 || user_id <= 0

    DB.execute("DELETE FROM liste_modello WHERE id = ? AND creato_da = ?", [modello_id, user_id])
    DB.changes > 0
  end

  def self.richiama(modello_id, gruppo_id_target, user_id, topic_id_target = 0)
    modello = trova(modello_id)
    return nil unless modello

    items = begin
      JSON.parse(modello["items_raw"].to_s)
    rescue JSON::ParserError
      []
    end
    items = Array(items).map(&:to_s)

    ids_creati = []
    items.each do |riga|
      ids = DataManager.aggiungi_articoli(
        gruppo_id: gruppo_id_target.to_i,
        user_id: user_id,
        items_text: riga,
        topic_id: topic_id_target.to_i,
        split_items: false
      )
      ids_creati.concat(Array(ids))
    end

    { nome: modello["nome"], count: items.size, ids: ids_creati }
  end
end
