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
        # Usa il metodo DRY unificato da DataManager (parametri creato_da e comprato_da opzionali)
        DataManager.upsert_storico_articolo(gruppo_id, topic_id, nome)
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
    puts "sono in genera_tastiera_checklist"
    suggerimenti = self.suggerimenti_per_checklist(gruppo_id, topic_id)
    puts "suggerimenti #{suggerimenti}"
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

  # In storico_manager.rb
  def self.ultimi_acquisti(gruppo_id, topic_id, limite = 15)
    begin
      puts "🕒 [STORICO] Recupero flusso acquisti per G:#{gruppo_id}"
      # Usiamo il nuovo metodo di db.rb
      DataManager.prendi_ultimi_acquisti_con_nomi(gruppo_id, topic_id, limite)
    rescue => e
      puts "❌ Errore: #{e.message}"
      []
    end
  end

  def self.formatta_storico(acquisti)
    return "🕒 *Ultimi acquisti*\n\nNessun dato." if acquisti.empty?

    righe = acquisti.map do |row|
      # Accorciamo il nome a 10 caratteri per stare nei margini mobile
      nome = row["nome"][0, 10].ljust(10)

      # Se il buyer è ancora ??, mostriamo solo l'autore per pulizia
      if row["buyer_init"] == "??"
        flusso = "#{row["autore_init"]}".center(7)
      else
        flusso = "#{row["autore_init"]}->#{row["buyer_init"]}".ljust(7)
      end

      data = Time.parse(row["updated_at"]).strftime("%d/%m")

      "`#{nome} #{flusso} #{data}`"
    end

    "🕒 *Ultimi acquisti*\n\n" + righe.join("\n")
  end
end
