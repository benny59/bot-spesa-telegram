# handlers/storico_manager.rb
class StoricoManager
  # Selezioni temporanee per utente (toggle checklist)
  @@selezioni_checklist = Hash.new { |h, k| h[k] = [] }

  # ========================================
  # 📊 AGGIORNA STORICO - Per toggle articoli
  # ========================================
def self.aggiorna_da_toggle(nome_articolo, gruppo_id, incremento, topic_id)
  nome_normalizzato = nome_articolo.downcase.strip
  topic_id ||= 0

  puts "📊 Storico toggle: #{nome_normalizzato} gruppo #{gruppo_id} topic #{topic_id} (#{incremento})"

  storico = DB.get_first_row(
    "SELECT * FROM storico_articoli
     WHERE nome = ?
       AND gruppo_id = ?
       AND COALESCE(topic_id,0) = ?",
    [nome_normalizzato, gruppo_id, topic_id]
  )

  return if incremento < 0 && !storico

  if storico
    nuovo = [storico["conteggio"] + incremento, 0].max
    DB.execute(
      "UPDATE storico_articoli
       SET conteggio = ?,
           ultima_aggiunta = CASE WHEN ? > 0 THEN datetime('now') ELSE ultima_aggiunta END,
           updated_at = datetime('now')
       WHERE id = ?",
      [nuovo, incremento, storico["id"]]
    )
  elsif incremento > 0
    DB.execute(
      "INSERT INTO storico_articoli
       (nome, gruppo_id, topic_id, conteggio, ultima_aggiunta, updated_at)
       VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
      [nome_normalizzato, gruppo_id, topic_id]
    )
  end
end

  # ========================================
  # ➕ AGGIORNA STORICO - Per aggiunta articoli
  # ========================================
def self.aggiorna_da_aggiunta(nome_articolo, gruppo_id, topic_id)
  nome_normalizzato = nome_articolo.downcase.strip
  topic_id ||= 0

  puts "📊 Storico aggiunta: #{nome_normalizzato} gruppo #{gruppo_id} topic #{topic_id}"

  storico = DB.get_first_row(
    "SELECT * FROM storico_articoli
     WHERE nome = ?
       AND gruppo_id = ?
       AND COALESCE(topic_id,0) = ?",
    [nome_normalizzato, gruppo_id, topic_id]
  )

  if storico
    DB.execute(
      "UPDATE storico_articoli
       SET conteggio = conteggio + 1,
           ultima_aggiunta = datetime('now'),
           updated_at = datetime('now')
       WHERE id = ?",
      [storico["id"]]
    )
  else
    DB.execute(
      "INSERT INTO storico_articoli
       (nome, gruppo_id, topic_id, conteggio, ultima_aggiunta, updated_at)
       VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
      [nome_normalizzato, gruppo_id, topic_id]
    )
  end
end

  # ========================================
  # 📋 GET TOP ARTICOLI - Per checklist
def self.top_articoli(gruppo_id, topic_id, limite = 10)
  begin
    puts "🔍 [TOP_ARTICOLI] Cerco articoli frequenti NON in lista per gruppo #{gruppo_id} topic #{topic_id}"

    result = DB.execute(
      "SELECT s.nome, s.conteggio, s.ultima_aggiunta
       FROM storico_articoli s
       WHERE s.gruppo_id = ?
         AND s.topic_id  = ?
         AND s.conteggio > 0
         AND NOT EXISTS (
           SELECT 1
           FROM items i
           WHERE i.gruppo_id = s.gruppo_id
             AND i.topic_id  = s.topic_id
             AND LOWER(i.nome) = LOWER(s.nome)
             AND i.comprato IS NULL
         )
       ORDER BY s.conteggio DESC, s.ultima_aggiunta DESC
       LIMIT ?",
      [gruppo_id, topic_id, limite]
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
def self.genera_checklist(bot, message, gruppo_id, topic_id = nil)

  chat_id  = message.chat.id
  user_id  = message.from.id
  topic_id = message.message_thread_id || 0

  puts "🔍 [CHECKLIST] Richiesta per gruppo #{gruppo_id} topic #{topic_id}"

   top_articoli = self.top_articoli(gruppo_id, topic_id, 10)

  if top_articoli.empty?
    bot.api.send_message(
      chat_id: chat_id,
      message_thread_id: topic_id,
      text: "📊 *Checklist Articoli Frequenti*\n\nNessun articolo disponibile.",
      parse_mode: "Markdown",
    )
    return
  end

  context_key = "#{user_id}:#{topic_id}"
  @@selezioni_checklist[context_key] ||= []

  righe = top_articoli.map do |articolo|
    nome = articolo["nome"]
    conteggio = articolo["conteggio"]
    selezionato = @@selezioni_checklist[context_key].include?(nome) ? "✅" : "➕"

    [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{selezionato} #{nome.capitalize} (#{conteggio}x)",
        callback_data: "checklist_toggle:#{nome}:#{gruppo_id}:#{user_id}:#{topic_id}",
      ),
    ]
  end

  righe << [
    Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "✅ Conferma aggiunta",
      callback_data: "checklist_confirm:#{gruppo_id}:#{user_id}:#{topic_id}",
    ),
    Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "❌ Chiudi",
      callback_data: "checklist_close:#{chat_id}:#{topic_id}",
    ),
  ]

  markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe)

  bot.api.send_message(
    chat_id: chat_id,
    message_thread_id: topic_id,
    text: "📋 *Checklist Articoli Frequenti*\n\nSeleziona gli articoli da aggiungere:",
    parse_mode: "Markdown",
    reply_markup: markup,
  )

  puts "✅ [CHECKLIST] Checklist inviata nel topic #{topic_id}"
end

  # ========================================
  # 🔁 GESTIONE TOGGLE ARTICOLI
  # ========================================
def self.gestisci_toggle_checklist(bot, msg, callback_data)
  if callback_data =~ /^checklist_toggle:(.+):(\d+):(\d+):(\d+)$/
    nome_articolo = $1
    gruppo_id     = $2.to_i
    user_id       = $3.to_i
    topic_id      = $4.to_i

    context_key = "#{user_id}:#{topic_id}"
    @@selezioni_checklist[context_key] ||= []
    selezioni = @@selezioni_checklist[context_key]

    if selezioni.include?(nome_articolo)
      selezioni.delete(nome_articolo)
    else
      selezioni << nome_articolo
    end

    top_articoli = self.top_articoli(gruppo_id, topic_id, 10)

    righe = top_articoli.map do |articolo|
      nome = articolo["nome"].capitalize
      conteggio = articolo["conteggio"]
      selezionato = selezioni.include?(articolo["nome"]) ? "✅" : "➕"

      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{selezionato} #{nome} (#{conteggio}x)",
          callback_data: "checklist_toggle:#{articolo["nome"]}:#{gruppo_id}:#{user_id}:#{topic_id}",
        ),
      ]
    end

    righe << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "✅ Conferma aggiunta",
        callback_data: "checklist_confirm:#{gruppo_id}:#{user_id}:#{topic_id}",
      ),
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "checklist_close:#{msg.message.chat.id}:#{topic_id}",
      ),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe)

    bot.api.edit_message_reply_markup(
      chat_id: msg.message.chat.id,
      message_thread_id: topic_id,
      message_id: msg.message.message_id,
      reply_markup: markup,
    )

    bot.api.answer_callback_query(callback_query_id: msg.id)
    return true
  end

  false
end

  # ========================================
  # ✅ CONFERMA SELEZIONI
  # ========================================
def self.gestisci_conferma_checklist(bot, msg, callback_data)
  # Modifica la regex per catturare anche topic_id
  if callback_data =~ /^checklist_confirm:(\d+):(\d+):(\d+)$/
    gruppo_id = $1.to_i
    user_id   = $2.to_i
    topic_id  = $3.to_i
    chat_id   = msg.message.chat.id

    context_key = "#{user_id}:#{topic_id}"
    selezioni = @@selezioni_checklist[context_key] || []
    
    return false if selezioni.empty?

    aggiunti = []

    selezioni.each do |nome_articolo|
      esistente = DB.get_first_row(
        "SELECT 1 FROM items 
         WHERE gruppo_id = ? 
           AND topic_id = ?
           AND LOWER(nome) = LOWER(?)
           AND comprato IS NULL",
        [gruppo_id, topic_id, nome_articolo]
      )
      next if esistente

      DB.execute(
        "INSERT INTO items (nome, gruppo_id, topic_id, creato_da, creato_il) 
         VALUES (?, ?, ?, ?, datetime('now'))",
        [nome_articolo.capitalize, gruppo_id, topic_id, user_id]
      )
      self.aggiorna_da_aggiunta(nome_articolo, gruppo_id, topic_id)
      aggiunti << nome_articolo.capitalize
    end

    # Pulisci le selezioni per questo contesto
    @@selezioni_checklist.delete(context_key)

    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: msg.message.message_id,
      message_thread_id: topic_id,
      text: "✅ Aggiunti: #{aggiunti.join(", ")}",
      parse_mode: "Markdown",
    )

    # Aggiorna la lista nel topic corretto
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, nil, 0, topic_id)
    bot.api.answer_callback_query(callback_query_id: msg.id)
    return true
  end
  false
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
        message_thread_id: topic_id,
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
  if callback_data =~ /^checklist_close:(-?\d+):(\d+)$/
    chat_id  = $1.to_i
    topic_id = $2.to_i

    puts "🖱 [CHECKLIST] Chiudi per chat #{chat_id} topic #{topic_id}"

    begin
      bot.api.delete_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        message_id: msg.message.message_id,
      )

      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "Checklist chiusa",
      )
    rescue => e
      puts "❌ Errore chiusura checklist: #{e.message}"

      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "❌ Errore chiusura",
      )
    end

    return true
  end

  false
end
end
