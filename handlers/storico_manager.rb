# handlers/storico_manager.rb
class StoricoManager
  # ========================================
  # 📊 AGGIORNA STORICO - Per toggle articoli
  # ========================================
  def self.aggiorna_da_toggle(nome_articolo, gruppo_id, incremento)
    nome_normalizzato = nome_articolo.downcase.strip

    puts "📊 Storico toggle: #{nome_normalizzato} gruppo #{gruppo_id} (+#{incremento})"

    storico = DB.get_first_row(
      "SELECT * FROM storico_articoli WHERE nome = ? AND gruppo_id = ?",
      [nome_normalizzato, gruppo_id]
    )

    if storico
      nuovo_conteggio = [storico["conteggio"] + incremento, 0].max
      DB.execute(
        "UPDATE storico_articoli SET conteggio = ?, ultima_aggiunta = ?, updated_at = datetime('now') WHERE id = ?",
        [nuovo_conteggio, incremento > 0 ? Time.now.to_s : storico["ultima_aggiunta"], storico["id"]]
      )
      puts "📊 Storico aggiornato: #{nome_normalizzato} → #{nuovo_conteggio}"
    elsif incremento > 0
      DB.execute(
        "INSERT INTO storico_articoli (nome, gruppo_id, conteggio, ultima_aggiunta) VALUES (?, ?, ?, ?)",
        [nome_normalizzato, gruppo_id, 1, Time.now.to_s]
      )
      puts "📊 Nuovo record storico: #{nome_normalizzato}"
    end
  rescue => e
    puts "❌ Errore aggiornamento storico toggle: #{e.message}"
  end

  # ========================================
  # ➕ AGGIORNA STORICO - Per aggiunta articoli
  # ========================================
  def self.aggiorna_da_aggiunta(nome_articolo, gruppo_id)
    nome_normalizzato = nome_articolo.downcase.strip

    puts "📊 Storico aggiunta: #{nome_normalizzato} gruppo #{gruppo_id}"

    storico = DB.get_first_row(
      "SELECT * FROM storico_articoli WHERE nome = ? AND gruppo_id = ?",
      [nome_normalizzato, gruppo_id]
    )

    if storico
      nuovo_conteggio = storico["conteggio"] + 1
      DB.execute(
        "UPDATE storico_articoli SET conteggio = ?, ultima_aggiunta = datetime('now'), updated_at = datetime('now') WHERE id = ?",
        [nuovo_conteggio, storico["id"]]
      )
      puts "📊 Storico aggiornato: #{nome_normalizzato} → #{nuovo_conteggio}"
    else
      DB.execute(
        "INSERT INTO storico_articoli (nome, gruppo_id, conteggio, ultima_aggiunta) VALUES (?, ?, ?, datetime('now'))",
        [nome_normalizzato, gruppo_id, 1]
      )
      puts "📊 Nuovo record storico: #{nome_normalizzato}"
    end
  rescue => e
    puts "❌ Errore aggiornamento storico aggiunta: #{e.message}"
  end

  # ========================================
  # 📋 GET TOP ARTICOLI - Per checklist
  # ========================================
  def self.top_articoli(gruppo_id, limite = 10)
    begin
      puts "🔍 [TOP_ARTICOLI] Cerco articoli frequenti NON in lista per gruppo #{gruppo_id}"

      result = DB.execute(
        "SELECT s.nome, s.conteggio, s.ultima_aggiunta 
       FROM storico_articoli s
       WHERE s.gruppo_id = ? 
         AND s.conteggio > 0 
         AND NOT EXISTS (
           SELECT 1 FROM items i 
           WHERE i.gruppo_id = s.gruppo_id 
           AND LOWER(i.nome) = LOWER(s.nome) 
         )
       ORDER BY s.conteggio DESC, s.ultima_aggiunta DESC 
       LIMIT ?",
        [gruppo_id, limite]
      )
      puts "🔍 [TOP_ARTICOLI] Risultato query: #{result.inspect}"
      puts "🔍 [TOP_ARTICOLI] Articoli frequenti non in lista: #{result.length}"
      result
    rescue => e
      puts "❌ Errore recupero top articoli: #{e.message}"
      []
    end
  end
  # ========================================
  # 🔍 GET CHECKLIST - Comando /checklist
  # ========================================
  def self.genera_checklist(bot, message, gruppo_id)
    chat_id = message.chat.id
    user_id = message.from.id

    puts "🔍 [CHECKLIST] Richiesta per gruppo #{gruppo_id}"

    top_articoli = self.top_articoli(gruppo_id, 10)

    if top_articoli.empty?
      bot.api.send_message(
        chat_id: chat_id,
        text: "📊 *Checklist Articoli Frequenti*\n\nNessun articolo nello storico per questo gruppo.\n\nInizia aggiungendo articoli con /+ per popolare la checklist!",
        parse_mode: "Markdown",
      )
      return
    end

    puts "🔍 [CHECKLIST] Genero tastiera con #{top_articoli.length} articoli"

    # Crea i pulsanti per gli articoli
    righe = top_articoli.map do |articolo|
      nome = articolo["nome"].capitalize
      conteggio = articolo["conteggio"]

      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "➕ #{nome} (#{conteggio}x)",
          callback_data: "checklist_add:#{articolo["nome"]}:#{gruppo_id}:#{user_id}",
        ),
      ]
    end

    # Aggiungi pulsante chiudi
    righe << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "checklist_close:#{chat_id}",
      ),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe)

    bot.api.send_message(
      chat_id: chat_id,
      text: "📋 *Checklist Articoli Frequenti*\n\nClicca '+' per aggiungere direttamente alla lista:",
      parse_mode: "Markdown",
      reply_markup: markup,
    )

    puts "✅ [CHECKLIST] Checklist inviata con successo"
  end

  # Aggiungi in storico_manager.rb
  def self.gestisci_click_checklist(bot, msg, callback_data)
    chat_id = msg.message.chat.id
    user_id = msg.from.id

    if callback_data =~ /^checklist_add:(.+):(\d+):(\d+)$/
      nome_articolo = $1
      gruppo_id = $2.to_i
      requested_user_id = $3.to_i

      puts "🖱 [CHECKLIST] Aggiungi: #{nome_articolo} per gruppo #{gruppo_id}"

      # Verifica che l'utente che clicca sia lo stesso per cui è stato generato il pulsante
      if user_id != requested_user_id
        bot.api.answer_callback_query(
          callback_query_id: msg.id,
          text: "❌ Questo pulsante non è per te!",
          show_alert: false,
        )
        return
      end

      # Recupera il gruppo
      gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [gruppo_id])

      if gruppo.nil?
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Gruppo non trovato")
        return
      end

      # Verifica se l'articolo è già nella lista
      articolo_esistente = DB.get_first_row(
        "SELECT * FROM items WHERE gruppo_id = ? AND LOWER(nome) = LOWER(?) AND comprato IS NULL",
        [gruppo_id, nome_articolo]
      )

      if articolo_esistente
        bot.api.answer_callback_query(
          callback_query_id: msg.id,
          text: "❌ #{nome_articolo.capitalize} è già nella lista!",
          show_alert: false,
        )
        return
      end

      # Aggiungi l'articolo
      DB.execute(
        "INSERT INTO items (nome, gruppo_id, creato_da, creato_il) VALUES (?, ?, ?, datetime('now'))",
        [nome_articolo.capitalize, gruppo_id, user_id]
      )

      # Aggiorna lo storico
      self.aggiorna_da_aggiunta(nome_articolo, gruppo_id)

      # Conferma all'utente
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "✅ #{nome_articolo.capitalize} aggiunto!",
        show_alert: false,
      )

      # Aggiorna il messaggio checklist
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: msg.message.message_id,
        text: "✅ *#{nome_articolo.capitalize}* aggiunto dalla checklist!",
        parse_mode: "Markdown",
      )

      # Aggiorna la lista principale
      KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id)

      return true
    end

    return false
  end
  def self.gestisci_chiusura_checklist(bot, msg, callback_data)
    if callback_data =~ /^checklist_close:(-?\d+)$/
      chat_id = $1.to_i

      puts "🖱 [CHECKLIST] Chiudi per chat #{chat_id}"

      begin
        bot.api.delete_message(
          chat_id: chat_id,
          message_id: msg.message.message_id,
        )
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "Checklist chiusa")
      rescue => e
        puts "❌ Errore chiusura checklist: #{e.message}"
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "✅")
      end

      return true
    end

    return false
  end
end
