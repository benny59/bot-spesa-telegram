# handlers/storico_manager.rb
require_relative "../db"

class StoricoManager

  # ==============================================================================
  # 1. IL MOTORE DELLA SCOPETTA (Business Logic del +1)
  # ==============================================================================
  # Questo metodo viene chiamato dal DataManager durante la pulizia.
  # Incrementa il conteggio solo per gli articoli effettivamente comprati.
  def self.registra_acquisto_batch(articoli_nomi, gruppo_id, topic_id)
    return if articoli_nomi.empty?

    DB.transaction do
      articoli_nomi.each do |nome|
        nome_norm = nome.downcase.strip

        # UPSERT: Se esiste incrementa, altrimenti crea.
        # Usiamo ON CONFLICT per garantire l'atomicità se hai l'indice UNIQUE,
        # altrimenti usiamo la logica UPDATE + INSERT.

        updated = DB.execute(
          "UPDATE storico_articoli 
           SET conteggio = conteggio + 1, 
               ultima_aggiunta = datetime('now'), 
               updated_at = datetime('now')
           WHERE nome = ? AND gruppo_id = ? AND topic_id = ?",
          [nome_norm, gruppo_id, topic_id]
        )

        if DB.changes == 0
          DB.execute(
            "INSERT INTO storico_articoli (nome, gruppo_id, topic_id, conteggio, ultima_aggiunta, updated_at)
             VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
            [nome_norm, gruppo_id, topic_id]
          )
        end
      end
    end
    puts "[STORICO] 📈 Incrementato storico per #{articoli_nomi.size} articoli."
  end

  # ==============================================================================
  # 2. SUGGERIMENTI PER LA CHECKLIST (Il tuo uso al supermercato)
  # ==============================================================================
  # Restituisce i 15 articoli più frequenti che NON sono già in lista.
  # handlers/storico_manager.rb
  # Recupera i suggerimenti marcando quelli già presenti in lista
  def self.suggerimenti_per_checklist(gruppo_id, topic_id)
    sql = <<~SQL
      SELECT s.nome, s.conteggio,
      (SELECT 1 FROM items i 
       WHERE i.gruppo_id = s.gruppo_id 
       AND i.topic_id = s.topic_id 
       AND LOWER(i.nome) = LOWER(s.nome) 
       AND (i.comprato IS NULL OR i.comprato = '')) as in_lista
      FROM storico_articoli s
      WHERE s.gruppo_id = ? AND s.topic_id = ?
      ORDER BY s.conteggio DESC, s.ultima_aggiunta DESC
      LIMIT 15
    SQL
    DB.execute(sql, [gruppo_id, topic_id])
  end

  def self.genera_tastiera_checklist(bot, context, gruppo_id, topic_id)
    suggerimenti = self.suggerimenti_per_checklist(gruppo_id, topic_id)
    return nil if suggerimenti.empty?

    keyboard = []
    suggerimenti.each_slice(2) do |coppia|
      row = coppia.map do |item|
        # 1. Recuperiamo il conteggio dallo storico (passato dal DataManager)
        volte = item["conteggio"].to_i
        label_count = volte > 0 ? " (#{volte})" : ""

        # 2. Prepariamo la label: es. "✅ Pane (12)" o "+ Latte (5)"
        status_prefix = item["in_lista"] ? "✅" : "+"
        label = "#{status_prefix} #{item["nome"].capitalize}#{label_count}"

        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: label,
          callback_data: "add_from_hist:#{item["nome"]}:#{gruppo_id}:#{topic_id}",
        )
      end
      keyboard << row
    end

    keyboard << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "🔙 Torna alla Lista", callback_data: "ui_back_to_list:#{gruppo_id}:#{topic_id}")]

    Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
  end
end
