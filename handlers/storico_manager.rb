# handlers/storico_manager.rb
require_relative "../db"
require "time"
require "cgi"

class StoricoManager

  YUKA_MARKER = /\[YUKA_LINK\]/i
  URL_REGEX = %r{https?://\S+}i

  def self.nome_storico_per_telegram(raw)
    nome = raw.to_s.dup
    nome = nome.gsub(/\[?YUKA_LINK\]?/i, " ")
    nome = nome.gsub(URL_REGEX, " ")
    nome = nome.gsub(/\s+/, " ").strip
    nome.empty? ? "Prodotto" : nome
  end

  def self.notifica_acquisto_html(nome, articoli)
    nome_sicuro = CGI.escapeHTML(nome.to_s)
    elenco = articoli.map { |articolo| CGI.escapeHTML(articolo.to_s) }.join(', ')
    return "🧹 <b>#{nome_sicuro}</b> ha pulito la lista." if elenco.empty?

    "🛒 <b>#{nome_sicuro}</b> ha comprato #{elenco}."
  end

  def self.notifica_scopetta_html(nome, comprati: [], cancellati: [])
    nome_sicuro = CGI.escapeHTML(nome.to_s)
    comprati = Array(comprati).map { |articolo| CGI.escapeHTML(articolo.to_s) }
    cancellati = Array(cancellati).map { |articolo| CGI.escapeHTML(articolo.to_s) }

    if comprati.empty? && cancellati.empty?
      return "🧹 <b>#{nome_sicuro}</b> ha pulito la lista."
    end

    parti = []
    parti << "🛒 <b>#{nome_sicuro}</b> ha comprato #{comprati.join(', ')}." unless comprati.empty?
    parti << "🗑️ <b>#{nome_sicuro}</b> ha eliminato definitivamente #{cancellati.join(', ')} senza averli comprati." unless cancellati.empty?

    parti.join("\n")
  end

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
      SELECT s.id, s.nome, s.link_url, s.conteggio, s.last_categoria_id, s.metadata_json,
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
        nome_label = nome_storico_per_telegram(item["nome"]).capitalize

        # 2. Prepariamo la label: es. "✅ Pane (12)" o "+ Latte (5)"
        status_prefix = item["in_lista"] ? "✅" : "+"
        label = "#{status_prefix} #{nome_label}#{label_count}"

        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: label,
          callback_data: "add_from_hist_id:#{item["id"]}:#{gruppo_id}:#{topic_id}",
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
    return "🕒 <b>Ultimi acquisti</b>\n\nNessun dato." if acquisti.empty?

    righe = acquisti.map do |acquisto|
      data = Time.parse(acquisto["updated_at"]).strftime("%d/%m/%Y %H:%M")
      acquirente = CGI.escapeHTML(acquisto["acquirente"].to_s)
      creatore = CGI.escapeHTML(acquisto["creatore"].to_s)
      nome = CGI.escapeHTML(nome_storico_per_telegram(acquisto["nome"]))
      identita = if acquisto["creato_da"] && acquisto["comprato_da"] &&
                    acquisto["creato_da"].to_i != acquisto["comprato_da"].to_i
          "Inserito da #{creatore} • acquistato da #{acquirente}"
        else
          "Acquistato da #{acquirente}"
        end
      "<b>#{nome}</b> — #{identita} — #{data}"
    end

    "🕒 <b>Ultimi acquisti</b>\n\n" + righe.join("\n\n")
  end
end
