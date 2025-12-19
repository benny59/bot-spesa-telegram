# handlers/carte_fedelta_gruppo.rb
require_relative "./carte_fedelta"

class CarteFedeltaGruppo < CarteFedelta
  # Ora usiamo le tabelle unificate
  CARDS_TABLE = "carte_fedelta"
  GROUP_LINKS_TABLE = "gruppo_carte_collegamenti"

  # Setup database per le carte gruppo
  def self.setup_db
    # Le tabelle sono già create in db.rb, qui verifichiamo solo la struttura
    aggiorna_schema_db_gruppo
  end

  # Aggiungi carta condivisa al gruppo
  def self.add_group_card(bot, chat_id, gruppo_id, user_id, args)
    parts = args.split(" ", 2)
    if parts.size < 2
      bot.api.send_message(chat_id: chat_id, text: "❌ Usa: /addcartagruppo NOME CODICE")
      return false
    end

    nome, codice = parts

    begin
      # Prima crea la carta nella tabella principale
      result = genera_barcode_con_nome(codice, nome, "gruppo_#{gruppo_id}")

      # Inserisci nella tabella carte_fedelta
      carta_id = DB.execute(
        "INSERT INTO #{CARDS_TABLE} (user_id, nome, codice, immagine_path) VALUES (?, ?, ?, ?)",
        [user_id, nome, codice, result[:img_path]]
      ).last_insert_row_id

      # Poi collega la carta al gruppo
      DB.execute(
        "INSERT INTO #{GROUP_LINKS_TABLE} (gruppo_id, carta_id, added_by) VALUES (?, ?, ?)",
        [gruppo_id, carta_id, user_id]
      )

      if File.exist?(result[:img_path])
        bot.api.send_photo(
          chat_id: chat_id,
          photo: Faraday::UploadIO.new(result[:img_path], "image/png"),
          caption: "✅ Carta #{nome} aggiunta al gruppo! (Formato: #{result[:formato]})",
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "✅ Carta #{nome} aggiunta al gruppo! (ma immagine non generata)")
      end
      return true
    rescue SQLite3::ConstraintException => e
      if e.message.include?("UNIQUE constraint failed")
        bot.api.send_message(chat_id: chat_id, text: "❌ Questa carta è già stata aggiunta al gruppo.")
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'aggiunta della carta al gruppo: #{e.message}")
      end
      return false
    rescue => e
      puts "❌ Errore aggiunta carta gruppo: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'aggiunta della carta al gruppo: #{e.message}")
      return false
    end
  end

  def self.show_user_shared_cards_report(bot, user_id)
    # Trova tutte le carte condivise dall'utente in tutti i gruppi
    carte_condivise = DB.execute("
    SELECT c.*, g.nome as gruppo_nome, gcl.gruppo_id
    FROM #{CARDS_TABLE} c 
    JOIN #{GROUP_LINKS_TABLE} gcl ON c.id = gcl.carta_id 
    JOIN gruppi g ON gcl.gruppo_id = g.id 
    WHERE c.user_id = ? 
    ORDER BY g.nome, LOWER(c.nome) ASC",
                                 [user_id])

    if carte_condivise.empty?
      bot.api.send_message(
        chat_id: user_id,
        text: "📊 Non hai condiviso carte in nessun gruppo.\nUsa /addcartagruppo nei gruppi per condividere le tue carte.",
      )
      return
    end

    # Raggruppa per gruppo
    carte_per_gruppo = carte_condivise.group_by { |c| c["gruppo_nome"] }

    # Costruisci il report
    report = "📊 *Le tue carte condivise per gruppo:*\n\n"

    carte_per_gruppo.each do |gruppo_nome, carte|
      report += "🏢 *#{gruppo_nome}*\n"
      carte.each do |carta|
        report += "  • #{carta["nome"]} (ID: #{carta["id"]})\n"
      end
      report += "\n"
    end

    report += "ℹ️ Per eliminare una carta, usa /delcartagruppo ID nel gruppo corrispondente."

    bot.api.send_message(
      chat_id: user_id,
      text: report,
      parse_mode: "Markdown",
    )
  end

  # Mostra carte del gruppo
def self.show_group_cards(bot, gruppo_id, chat_id, user_id, topic_id = 0)
  carte = DB.execute(
    "
    SELECT c.id, c.nome, c.user_id, u.full_name
    FROM #{CARDS_TABLE} c
    JOIN #{GROUP_LINKS_TABLE} gcl ON c.id = gcl.carta_id
    LEFT JOIN whitelist u ON c.user_id = u.user_id
    WHERE gcl.gruppo_id = ?
    ORDER BY LOWER(c.nome) ASC
    ",
    [gruppo_id]
  )

  if carte.empty?
    bot.api.send_message(
      chat_id: chat_id,
      message_thread_id: topic_id > 0 ? topic_id : nil,
      text: "⚠️ Nessuna carta condivisa nel gruppo.\nUsa /addcartagruppo NOME CODICE per aggiungerne una.",
    )
    return
  end

  inline_keyboard = []
  current_row = []

  carte.each_with_index do |row, index|
    current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
      text: row["nome"],
      callback_data: "carte_gruppo:#{gruppo_id}:#{row["id"]}",
    )

    if current_row.size == 4 || index == carte.size - 1
      inline_keyboard << current_row
      current_row = []
    end
  end

  # ✅ TASTO CHIUDI CORRETTO
  inline_keyboard << [
    Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "❌ Chiudi",
      callback_data: "carte_chiudi:#{chat_id}:#{topic_id}",
    ),
  ]

  keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

  bot.api.send_message(
    chat_id: chat_id,
    message_thread_id: topic_id > 0 ? topic_id : nil,
    text: "🏢 Carte condivise del gruppo:",
    reply_markup: keyboard,
  )
end

  def self.handle_delcartagruppo(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo

    text = msg.text.to_s
    text = text.gsub(/\/delcartagruppo(@\w+)?/, "").strip

    if text.empty?
      show_delete_interface(bot, gruppo["id"], user_id, chat_id)
    else
      carta_id = text.to_i
      if carta_id > 0
        delete_group_card(bot, gruppo["id"], user_id, carta_id)
      else
        # Cerca per nome
        carte = DB.execute("
          SELECT c.id, c.nome 
          FROM #{CARDS_TABLE} c 
          JOIN #{GROUP_LINKS_TABLE} gcl ON c.id = gcl.carta_id 
          WHERE gcl.gruppo_id = ? AND c.user_id = ? AND LOWER(c.nome) = LOWER(?)",
                           [gruppo["id"], user_id, text.strip])
        if carte.any?
          show_delete_interface(bot, gruppo["id"], user_id)
        else
          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Nessuna carta trovata con nome '#{text}'. Usa /delcartagruppo senza parametri per vedere le tue carte.",
          )
        end
      end
    end
  end

  # Elimina carta del gruppo (solo chi l'ha aggiunta)
  def self.delete_group_card(bot, gruppo_id, user_id, carta_id, chat_id = nil, is_link_id = false)
    if is_link_id
      # Se è un link_id, cerca direttamente il collegamento
      link = DB.execute("SELECT * FROM #{GROUP_LINKS_TABLE} WHERE id = ? AND gruppo_id = ?", [carta_id, gruppo_id]).first
      unless link
        target_chat = chat_id || user_id
        bot.api.send_message(chat_id: target_chat, text: "❌ Collegamento carta non trovato.")
        return false
      end

      # Recupera i dettagli della carta
      carta = DB.execute("SELECT * FROM #{CARDS_TABLE} WHERE id = ?", [link["carta_id"]]).first
      link_id = carta_id
      actual_carta_id = link["carta_id"]
    else
      # Se è un carta_id, cerca il collegamento
      link = DB.execute("SELECT * FROM #{GROUP_LINKS_TABLE} WHERE gruppo_id = ? AND carta_id = ?", [gruppo_id, carta_id]).first
      unless link
        target_chat = chat_id || user_id
        bot.api.send_message(chat_id: target_chat, text: "❌ Carta non trovata nel gruppo.")
        return false
      end

      carta = DB.execute("SELECT * FROM #{CARDS_TABLE} WHERE id = ?", [carta_id]).first
      link_id = link["id"]
      actual_carta_id = carta_id
    end

    unless carta
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "❌ Carta non trovata.")
      return false
    end

    if carta["user_id"] != user_id
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "❌ Puoi eliminare solo le carte che hai aggiunto tu.")
      return false
    end

    # Rimuovi il collegamento gruppo-carta
    DB.execute("DELETE FROM #{GROUP_LINKS_TABLE} WHERE id = ?", [link_id])

    # Verifica se la carta è ancora usata in altri gruppi
    altri_collegamenti = DB.execute("SELECT COUNT(*) as count FROM #{GROUP_LINKS_TABLE} WHERE carta_id = ?", [actual_carta_id]).first["count"]

    # Se non è più usata in nessun gruppo, elimina anche la carta e l'immagine
    if altri_collegamenti == 0
      DB.execute("DELETE FROM #{CARDS_TABLE} WHERE id = ?", [actual_carta_id])

      # Cancella l'immagine se esiste
      if carta["immagine_path"] && File.exist?(carta["immagine_path"])
        File.delete(carta["immagine_path"])
      end
    end

    target_chat = chat_id || user_id
    bot.api.send_message(chat_id: target_chat, text: "✅ Carta '#{carta["nome"]}' eliminata dal gruppo.")
    return true
  end

  # Mostra interfaccia per eliminare le proprie carte
  # handlers/carte_fedelta_gruppo.rb

  # Modifica solo show_delete_interface per avere 3 bottoni per riga
  def self.show_delete_interface(bot, gruppo_id, user_id, chat_id = nil)
    user_cards = DB.execute("
    SELECT c.id, c.nome, gcl.id as link_id 
    FROM #{CARDS_TABLE} c 
    JOIN #{GROUP_LINKS_TABLE} gcl ON c.id = gcl.carta_id 
    WHERE gcl.gruppo_id = ? AND c.user_id = ? 
    ORDER BY LOWER(c.nome) ASC",
                            [gruppo_id, user_id])

    if user_cards.empty?
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "⚠️ Non hai carte da eliminare nel gruppo.")
      return
    end

    inline_keyboard = []
    current_row = []

    user_cards.each_with_index do |card, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🗑️ #{card["nome"]}",
        callback_data: "carte_gruppo_confirm_delete:#{gruppo_id}:#{card["link_id"]}",
      )

      # 3 bottoni per riga invece di 1
      if current_row.size == 3 || index == user_cards.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "checklist_close:#{chat_id || user_id}", # Usa chat_id se disponibile, altrimenti user_id
      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    target_chat = chat_id || user_id
    bot.api.send_message(
      chat_id: target_chat,
      text: "Seleziona la carta da eliminare:",
      reply_markup: keyboard,
    )
  end

  def self.show_add_to_group_interface(bot, user_id, gruppo_id, chat_id = nil)
    # Recupera tutte le carte personali dell'utente
    carte_personali = DB.execute("
    SELECT id, nome, codice 
    FROM #{CARDS_TABLE} 
    WHERE user_id = ? 
    ORDER BY LOWER(nome) ASC",
                                 [user_id])

    if carte_personali.empty?
      bot.api.send_message(
        chat_id: user_id,
        text: "❌ Non hai ancora carte personali. Usa prima /addcarta per crearne una.",
      )
      return
    end

    # Recupera le carte già aggiunte al gruppo
    carte_gia_aggiunte = DB.execute("
    SELECT carta_id 
    FROM #{GROUP_LINKS_TABLE} 
    WHERE gruppo_id = ? AND added_by = ?",
                                    [gruppo_id, user_id]).map { |r| r["carta_id"] }

    inline_keyboard = []
    current_row = []

    carte_personali.each_with_index do |carta, index|
      # Determina se la carta è già nel gruppo
      gia_aggiunta = carte_gia_aggiunte.include?(carta["id"])

      icona = gia_aggiunta ? "✅" : "⬜"
      testo_bottone = "#{icona} #{carta["nome"]}"
      callback_data = gia_aggiunta ?
        "carte_gruppo_remove:#{gruppo_id}:#{carta["id"]}" :
        "carte_gruppo_add:#{gruppo_id}:#{carta["id"]}"

      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: testo_bottone,
        callback_data: callback_data,
      )

      # 3 bottoni per riga
      if current_row.size == 3 || index == carte_personali.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    # Bottone "Fine"
    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🏁 Fine",
        callback_data: "carte_gruppo_add_finish:#{gruppo_id}",
      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # Recupera il nome del gruppo
    gruppo = DB.execute("SELECT nome FROM gruppi WHERE id = ?", [gruppo_id]).first
    nome_gruppo = gruppo ? gruppo["nome"] : "Gruppo"

    bot.api.send_message(
      chat_id: user_id,
      text: "🏢 *Aggiungi/rimuovi carte dal gruppo: #{nome_gruppo}*\n\n" +
            "✅ = già nel gruppo\n⬜ = non nel gruppo\n\n" +
            "Clicca su una carta per aggiungerla o rimuoverla dal gruppo:",
      parse_mode: "Markdown",
      reply_markup: keyboard,
    )
  end

  def self.handle_addcartagruppo(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo

    # Invia l'interfaccia nella chat privata dell'utente
    show_add_to_group_interface(bot, user_id, gruppo["id"], chat_id)
  end
  def self.add_personal_card_to_group(bot, callback_query, gruppo_id, carta_id)
    user_id = callback_query.from.id

    begin
      # Verifica che la carta appartenga all'utente
      carta = DB.execute("SELECT * FROM #{CARDS_TABLE} WHERE id = ? AND user_id = ?", [carta_id, user_id]).first
      unless carta
        bot.api.send_message(chat_id: user_id, text: "❌ Carta non trovata.")
        return false
      end

      # Verifica che non sia già stata aggiunta
      existing = DB.execute("SELECT * FROM #{GROUP_LINKS_TABLE} WHERE gruppo_id = ? AND carta_id = ?", [gruppo_id, carta_id]).first
      if existing
        bot.api.send_message(chat_id: user_id, text: "❌ La carta '#{carta["nome"]}' è già nel gruppo.")
        return false
      end

      # Aggiungi il collegamento
      DB.execute(
        "INSERT INTO #{GROUP_LINKS_TABLE} (gruppo_id, carta_id, added_by) VALUES (?, ?, ?)",
        [gruppo_id, carta_id, user_id]
      )

      # Aggiorna solo il bottone
      update_toggle_button(bot, callback_query, gruppo_id, carta_id, true)

      return true
    rescue SQLite3::ConstraintException => e
      if e.message.include?("UNIQUE constraint failed")
        update_toggle_button(bot, callback_query, gruppo_id, carta_id, true) # Forza l'aggiornamento visivo
      else
        bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Errore nell'aggiunta")
      end
      return false
    rescue => e
      puts "❌ Errore aggiunta carta al gruppo: #{e.message}"
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Errore nell'aggiunta")
      return false
    end
  end

  # Rimuovi una carta personale dal gruppo
  def self.remove_personal_card_from_group(bot, callback_query, gruppo_id, carta_id)
    user_id = callback_query.from.id

    begin
      # Verifica che la carta appartenga all'utente
      carta = DB.execute("SELECT * FROM #{CARDS_TABLE} WHERE id = ? AND user_id = ?", [carta_id, user_id]).first
      unless carta
        bot.api.send_message(chat_id: user_id, text: "❌ Carta non trovata.")
        return false
      end

      # 🔥 APPROCCIO SEMPLICE: Rimuovi e aggiorna sempre l'interfaccia
      DB.execute("DELETE FROM #{GROUP_LINKS_TABLE} WHERE gruppo_id = ? AND carta_id = ? AND added_by = ?",
                 [gruppo_id, carta_id, user_id])

      # Aggiorna solo il bottone
      update_toggle_button(bot, callback_query, gruppo_id, carta_id, false)
      return true
    rescue => e
      puts "❌ Errore rimozione carta dal gruppo: #{e.message}"
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Errore nella rimozione")
      return false
    end
  end

  def self.update_toggle_button(bot, callback_query, gruppo_id, carta_id, added)
    user_id = callback_query.from.id

    # Recupera tutte le carte personali dell'utente
    carte_personali = DB.execute("
    SELECT id, nome, codice 
    FROM #{CARDS_TABLE} 
    WHERE user_id = ? 
    ORDER BY LOWER(nome) ASC",
                                 [user_id])

    # Recupera le carte già aggiunte al gruppo
    carte_gia_aggiunte = DB.execute("
    SELECT carta_id 
    FROM #{GROUP_LINKS_TABLE} 
    WHERE gruppo_id = ? AND added_by = ?",
                                    [gruppo_id, user_id]).map { |r| r["carta_id"] }

    # Ricostruisci la tastiera completa
    inline_keyboard = []
    current_row = []

    carte_personali.each_with_index do |carta, index|
      gia_aggiunta = carte_gia_aggiunte.include?(carta["id"])

      icona = gia_aggiunta ? "✅" : "⬜"
      testo_bottone = "#{icona} #{carta["nome"]}"
      callback_data = gia_aggiunta ?
        "carte_gruppo_remove:#{gruppo_id}:#{carta["id"]}" :
        "carte_gruppo_add:#{gruppo_id}:#{carta["id"]}"

      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: testo_bottone,
        callback_data: callback_data,
      )

      if current_row.size == 3 || index == carte_personali.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    # Bottone "Fine"
    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🏁 Fine",
        callback_data: "carte_gruppo_add_finish:#{gruppo_id}",
      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # Feedback immediato
    bot.api.answer_callback_query(
      callback_query_id: callback_query.id,
      text: added ? "✅ Carta aggiunta al gruppo" : "❌ Carta rimossa dal gruppo",
    )

    # Aggiorna solo la tastiera del messaggio
    bot.api.edit_message_reply_markup(
      chat_id: user_id,
      message_id: callback_query.message.message_id,
      reply_markup: keyboard,
    )
  end

  # Callback handling per carte gruppo
  def self.handle_callback(bot, callback_query)
    user_id = callback_query.from.id
    chat_id = callback_query.message.chat.id
    data = callback_query.data

    case data
    when /^carte_gruppo:(\d+):(\d+)$/
      gruppo_id, carta_id = $1.to_i, $2.to_i

      topic_id = callback_query.message.message_thread_id || 0
      puts "🧵 CARTE_GRUPPO topic_id=#{topic_id}"

      mostra_carta_gruppo(bot, chat_id, gruppo_id, carta_id, topic_id)
    when /^carte_gruppo_delete:(\d+):(\d+)$/
      gruppo_id, uid = $1.to_i, $2.to_i
      return if uid != user_id
      show_delete_interface(bot, gruppo_id, user_id, chat_id)
    when /^carte_gruppo_confirm_delete:(\d+):(\d+)$/
      gruppo_id, link_id = $1.to_i, $2.to_i
      delete_group_card(bot, gruppo_id, user_id, link_id, chat_id, true)
      show_group_cards(bot, gruppo_id, chat_id, user_id)
    when /^carte_gruppo_back:(\d+)$/
      gruppo_id = $1.to_i
      show_group_cards(bot, gruppo_id, chat_id, user_id)
    when /^carte_gruppo_add:(\d+):(\d+)$/
      gruppo_id, carta_id = $1.to_i, $2.to_i
      add_personal_card_to_group(bot, callback_query, gruppo_id, carta_id)
    when /^carte_gruppo_remove:(\d+):(\d+)$/
      gruppo_id, carta_id = $1.to_i, $2.to_i
      remove_personal_card_from_group(bot, callback_query, gruppo_id, carta_id)
      
 when /^carte_chiudi:(-?\d+):(\d+)$/
  chat_id  = $1.to_i
  topic_id = $2.to_i

  begin
    bot.api.delete_message(
      chat_id: chat_id,
      message_id: callback_query.message.message_id,
    )
  rescue => e
    puts "❌ Errore chiusura carte: #{e.message}"
  end

  bot.api.answer_callback_query(
    callback_query_id: callback_query.id,
    text: "Chiuse",
  )     
      
    when /^carte_gruppo_add_finish:(\d+)$/
      # 🔥 MODIFICA: Rimuovi la tastiera e mostra conferma
      bot.api.answer_callback_query(
        callback_query_id: callback_query.id,
        text: "✅ Configurazione completata!",
      )

      # Rimuovi la tastiera impostando reply_markup a nil
      bot.api.edit_message_reply_markup(
        chat_id: user_id,
        message_id: callback_query.message.message_id,
        reply_markup: nil, # 🔥 Questo fa scomparire la tastiera
      )

      # Opzionale: invia un messaggio di conferma separato
      bot.api.send_message(
        chat_id: user_id,
        text: "✅ Configurazione carte completata! Usa /cartegruppo nel gruppo per vedere le carte condivise.",
      )
    end
  end

  def self.mostra_carta_gruppo(bot, chat_id, gruppo_id, carta_id, topic_id = nil)
    row = DB.execute("
    SELECT c.* 
    FROM #{CARDS_TABLE} c 
    JOIN #{GROUP_LINKS_TABLE} gcl ON c.id = gcl.carta_id 
    WHERE c.id = ? AND gcl.gruppo_id = ?",
                     [carta_id, gruppo_id]).first

    if row
      img_path = row["immagine_path"]

      # Rigenera se necessario
      unless img_path && File.exist?(img_path) && File.size(img_path) > 100
        begin
          result = genera_barcode_con_nome(row["codice"], row["nome"], "gruppo_#{gruppo_id}")
          DB.execute("UPDATE #{CARDS_TABLE} SET immagine_path = ? WHERE id = ?",
                     [result[:img_path], carta_id])
          img_path = result[:img_path]
        rescue => e
          puts "❌ Rigenerazione carta gruppo fallita: #{e.message}"
          bot.api.send_message(chat_id: chat_id, text: "❌ Errore nella rigenerazione del barcode.")
          return
        end
      end

      if File.exist?(img_path)
        caption = "🏢 Carta Condivisa\n💳 #{row["nome"]}\n🔢 Codice: #{row["codice"]}"
        inline_keyboard = [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Chiudi",
              callback_data: "close_barcode",
            ),
          ],
        ]
        keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

        # 🔥 MODIFICA PRINCIPALE: Usa message_thread_id se topic_id > 0
        if topic_id
          bot.api.send_photo(
            chat_id: chat_id,
            message_thread_id: topic_id,
            photo: Faraday::UploadIO.new(img_path, "image/png"),
            caption: caption,
            reply_markup: keyboard,
          )
        else
          bot.api.send_photo(
            chat_id: chat_id,
            photo: Faraday::UploadIO.new(img_path, "image/png"),
            caption: caption,
            reply_markup: keyboard,
          )
        end
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Immagine non disponibile per #{row["nome"]}")
      end
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Carta non trovata nel gruppo.")
    end
  end

  private

  def self.aggiorna_schema_db_gruppo
    # Non serve più, le tabelle sono gestite in db.rb
    # Manteniamo il metodo per compatibilità ma non fa nulla
  end
end
