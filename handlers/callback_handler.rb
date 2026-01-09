# handlers/callback_handler.rb
require_relative "../models/lista"
require_relative "../models/group_manager"
require_relative "../models/whitelist"
require_relative "../models/preferences"
require_relative "../models/carte_fedelta"
require_relative "../models/carte_fedelta_gruppo"
require_relative "../utils/keyboard_generator"
require_relative "../utils/logger"
require_relative "../db"
require_relative "../utils/logger" unless defined?(Logger)

class CallbackHandler
  def self.route(bot, callback, context)
    Logger.debug("Callback ricevuto", data: callback.data)
    data = callback.data
    chat_id = callback.message.chat.id
    user_id = callback.from.id

    case data
    when /^lista_page:(\d+):(\d+):(\d+)$/
  gruppo_id = $1.to_i
  nuova_pagina = $2.to_i
  t_id = $3.to_i
  
  # Chiamiamo la generazione della lista passando la nuova pagina e il topic
  KeyboardGenerator.genera_lista(
    bot, 
    chat_id, 
    gruppo_id, 
    user_id, 
    callback.message.message_id, 
    nuova_pagina, 
    t_id
  )
  # Rispondiamo al callback per togliere lo spinner
  bot.api.answer_callback_query(callback_query_id: callback.id)
    # --- INIZIO BLOCCO FOTO CORRETTO ---
    when /^view_foto:(\d+):(\d+)(?::(\d+))?$/
      t_id = $3&.to_i || 0
      puts "📸 [DEBUG] Eseguo handle_view_foto per item #{$1} nel topic #{t_id}"
      handle_view_foto(bot, callback, chat_id, $1.to_i, $2.to_i, t_id)
    when /^cancel_foto:(\d+):(\d+)(?::(\d+))?$/
      puts "🧹 [DEBUG] Eseguo handle_cancel_foto"
      handle_cancel_foto(bot, callback, chat_id)
    when /^(add_foto|replace_foto):(\d+):(\d+)(?::(\d+))?$/
      t_id = $4&.to_i || 0
      puts "📝 [DEBUG] Eseguo handle_add_replace_foto per item #{$2}"
      handle_add_replace_foto(bot, callback, chat_id, $2.to_i, $3.to_i, t_id)
    when /^foto_menu:(\d+):(\d+)(?::(\d+))?$/
      t_id = $3&.to_i || 0
      handle_foto_menu(bot, callback, chat_id, $1.to_i, $2.to_i, t_id)
    when /^remove_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_remove_foto(bot, callback, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
      # --- FINE BLOCCO FOTO ---

    when "close_barcode"
      begin
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "✅ Chiuso", show_alert: false)
        bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id)
      rescue => e
        Logger.warn("close_barcode error", error: e.message) rescue nil
      end
    when /^carte_gruppo_add:(\d+):(\d+)$/, /^carte_gruppo_remove:(\d+):(\d+)$/, /^carte_gruppo_add_finish:(\d+)$/, /^carte_chiudi:(-?\d+):(\d+)$/
      CarteFedeltaGruppo.handle_callback(bot, callback)
    when /^carte:(\d+):(\d+)$/, "carte_delete", /^carte_confirm_delete:(\d+)$/, "carte_back"
      CarteFedelta.handle_callback(bot, callback)
    when /^mostra_carte:(\d+)(?::(\d+))?$/
      CarteFedeltaGruppo.show_group_cards(bot, $1.to_i, chat_id, user_id, ($2 || 0).to_i)
    when /^checklist_toggle:[^:]+:\d+:\d*:\d+$/
      handled = StoricoManager.gestisci_toggle_checklist(bot, callback, data)
      bot.api.answer_callback_query(callback_query_id: callback.id) unless handled
    when /^checklist_confirm:\d+:\d*:\d+$/
      handled = StoricoManager.gestisci_conferma_checklist(bot, callback, data)
      bot.api.answer_callback_query(callback_query_id: callback.id) unless handled
    when /^checklist_close:(-?\d+):(\d+)$/
      StoricoManager.gestisci_chiusura_checklist(bot, callback, data)
    when /^show_checklist:(\d+):(\d+)$/
      handle_show_checklist(bot, callback, chat_id, user_id, $1.to_i, $2.to_i)
    when /^show_storico:(\d+):(\d+)$/
      gruppo_id, t_id = $1.to_i, $2.to_i
      acquisti = StoricoManager.ultimi_acquisti(gruppo_id, t_id)
      testo = StoricoManager.formatta_storico(acquisti)
      keyboard = KeyboardGenerator.ui_close_keyboard(chat_id, t_id) # Usa il generatore se esiste, o InlineKeyboardMarkup
      bot.api.send_message(chat_id: chat_id, text: testo, parse_mode: "Markdown", message_thread_id: t_id, reply_markup: keyboard)
      bot.api.answer_callback_query(callback_query_id: callback.id)
    when /^comprato:(\d+):(\d+)(?::(\d+))?$/
      handle_comprato(bot, callback, chat_id, user_id, $1.to_i, $2.to_i, ($3 || context.topic_id).to_i)
    when /^cancella:(\d+):(\d+)(?::(\d+))?$/
      handle_cancella(bot, callback, chat_id, user_id, $1.to_i, $2.to_i, ($3 || 0).to_i)
    when /^info:(\d+):(\d+)(?::(\d+))?$/
      handle_info(bot, callback, $1.to_i, $2.to_i, ($3 || 0).to_i)
    when /^ui_close:(-?\d+):(\d+)$/
      gestisci_chiusura_ui(bot, callback, data)
    when "switch_to_group"
      DB.execute("DELETE FROM config WHERE key = ?", ["context:#{user_id}"])
      Context.show_group_selector(bot, user_id, callback.message.message_id)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "Modalità Gruppo ripristinata")
    when /^private_set:(-?\d+):(-?\d+):(\d+)$/
      db_id, c_id, t_id = $1.to_i, $2.to_i, $3.to_i
      t_row = DB.get_first_row("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [c_id, t_id])
      t_name = t_row ? t_row["nome"] : (t_id == 0 ? "Generale" : "Topic #{t_id}")
      config_value = { db_id: db_id, chat_id: c_id, topic_id: t_id, topic_name: t_name }.to_json
      DB.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", ["context:#{user_id}", config_value])
      Context.show_group_selector(bot, user_id, callback.message.message_id)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "✅ Modalità privata attiva")
    else
      puts "❓ Callback non gestita: #{data}"
      bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil
    end
  end

  def self.handle(bot, msg)
    # msg è l'oggetto CallbackQuery di Telegram
    chat_id = msg.message.respond_to?(:chat) ? msg.message.chat.id : msg.from.id
    user_id = msg.from.id
    topic_id = msg.message.message_thread_id || 0
    data = msg.data.to_s

    puts "🧵 CALLBACK topic_id=#{topic_id} | Data: #{data}"

    case data
    when "noop"
      handle_noop(bot, msg)

      # --- GESTIONE FOTO: Rotte mancanti ---
      # --- INIZIO BLOCCO FOTO ---
    when /^view_foto:(\d+):(\d+)(?::(\d+))?$/
      # $1: item_id, $2: gruppo_id, $3: topic_id
      t_id = $3&.to_i || 0
      puts "📸 [DEBUG] Eseguo handle_view_foto per item #{$1} nel topic #{t_id}"
      handle_view_foto(bot, msg, chat_id, $1.to_i, $2.to_i, t_id)
    when /^cancel_foto:(\d+):(\d+)(?::(\d+))?$/
      puts "🧹 [DEBUG] Eseguo handle_cancel_foto (chiusura sottomenu)"
      handle_cancel_foto(bot, msg, chat_id)
    when /^(add_foto|replace_foto):(\d+):(\d+)(?::(\d+))?$/
      t_id = $4&.to_i || 0
      puts "📝 [DEBUG] Eseguo handle_add_replace_foto per item #{$2}"
      handle_add_replace_foto(bot, msg, chat_id, $2.to_i, $3.to_i, t_id)
    when /^foto_menu:(\d+):(\d+)(?::(\d+))?$/
      t_id = $3&.to_i || 0
      handle_foto_menu(bot, msg, chat_id, $1.to_i, $2.to_i, t_id)
    when /^remove_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_remove_foto(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
      # --- FINE BLOCCO FOTO ---

    when /^foto_menu:(\d+):(\d+)(?::(\d+))?$/
      handle_foto_menu(bot, msg, chat_id, $1.to_i, $2.to_i, $3&.to_i || 0)

      # --- LISTA E ARTICOLI ---
    when /^comprato:(\d+):(\d+)(?::(\d+))?$/
      handle_comprato(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^cancella:(\d+):(\d+)(?::(\d+))?$/
      handle_cancella(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^lista_page:(\d+):(\d+)(?::(\d+))?$/
      handle_lista_page(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^aggiungi:(\d+)(?::(\d+))?$/
      handle_aggiungi(bot, msg, chat_id, $1.to_i, $2&.to_i || 0)
    when /^toggle:(\d+):(\d+)(?::(\d+))?$/
      handle_toggle(bot, msg, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^info:(\d+):(\d+)(?::(\d+))?$/
      handle_info(bot, msg, $1.to_i, $2.to_i, $3&.to_i || 0)

      # --- UI E CHIUSURA ---
    when /^ui_close:(-?\d+):(\d+)$/
      gestisci_chiusura_ui(bot, msg, data)
    when /^checklist_close:(-?\d+):(\d+)$/
      StoricoManager.gestisci_chiusura_checklist(bot, msg, data)

      # --- CARTE FEDELTÀ ---
    when /^mostra_carte:(\d+)(?::(\d+))?$/
      CarteFedeltaGruppo.show_group_cards(bot, $1.to_i, chat_id, user_id, topic_id)
    when "close_barcode", "carte_cancel_delete", /^carte:/, /^carte_gruppo/
      # Deleghiamo tutto ai gestori specifici passando l'oggetto msg (callback)
      if data.start_with?("carte_gruppo") || data.start_with?("carte_chiudi")
        CarteFedeltaGruppo.handle_callback(bot, msg)
      else
        CarteFedelta.handle_callback(bot, msg)
      end

      # --- STORICO E ALTRO ---
    when /^show_storico:(\d+):(\d+)$/
      handle_show_storico(bot, msg, chat_id, $1.to_i, $2.to_i)
    when /^myitems_(page|refresh):(\d+):(\d+)$/
      # Unificata la gestione myitems
      target_user_id = $2.to_i
      page = $3.to_i
      if target_user_id == user_id
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "Aggiorno...") if data.include?("refresh")
        MessageHandler.handle_myitems(bot, chat_id, user_id, msg.message, page)
      else
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Azione non permessa")
      end
    else
      puts "❌ Callback non riconosciuto: #{data}"
    end
  end

  private

  # 🔥 MODIFICA: Aggiungi topic_id ai metodi principali
  def self.handle_comprato(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    # Recuperiamo il nome dell'item prima del toggle per la notifica
    item_nome = DB.get_first_value("SELECT nome FROM items WHERE id = ?", [item_id])
    user_name = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || "Qualcuno"

    # Eseguiamo l'azione
    nuovo_stato = Lista.toggle_comprato(gruppo_id, item_id, user_id)

    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Stato aggiornato")

    # NOTIFICA
    emoji = (nuovo_stato.to_s.strip == "" || nuovo_stato.to_s == "0") ? "🔄" : "✅"
    azione = emoji == "✅" ? "ha preso" : "ha rimesso in lista"
    Context.notifica_gruppo_se_privato(bot, user_id, "#{emoji} *#{user_name}* #{azione}: #{item_nome}")

    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_cancella(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    item_nome = DB.get_first_value("SELECT nome FROM items WHERE id = ?", [item_id])
    user_name = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || "Qualcuno"

    Lista.cancella(gruppo_id, item_id, user_id)

    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Eliminato")

    # NOTIFICA
    Context.notifica_gruppo_se_privato(bot, user_id, "🗑️ *#{user_name}* ha rimosso: #{item_nome}")

    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_cancella_tutti(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    u_row = DB.get_first_row("SELECT first_name FROM user_names WHERE user_id = ?", [user_id])
    user_display = u_row ? u_row["first_name"] : "Utente #{user_id}"

    if Lista.cancella_tutti(gruppo_id, user_id)
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "✅ Articoli comprati rimossi")

      # NOTIFICA
      Context.notifica_gruppo_se_privato(bot, user_id, "🧹 *#{user_display}* ha rimosso tutti gli articoli completati.")

      KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
    else
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Solo admin può cancellare tutti")
    end
  end

  def self.handle_azioni_menu(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    has_image = Lista.ha_immagine?(item_id)
    item = Lista.trova(item_id)
    return unless item

    buttons = []
    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: item["comprato"] == 1 ? "❌ Segna da comprare" : "✅ Segna comprato",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "comprato:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    if has_image
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "👁️ Visualizza foto",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "view_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🔄 Sostituisci",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "replace_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🗑️ Rimuovi",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "remove_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
      ]
    else
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📷 Aggiungi foto",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "add_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
      ]
    end

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "ℹ️ Informazioni",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "toggle:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Cancella articolo",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "cancella:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "↩️ Torna alla lista",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "cancel_azioni:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "⚙️ *Menu azioni:* #{item["nome"]}",
      parse_mode: "Markdown",
      reply_markup: markup,
    )
  end

  def self.handle_noop(bot, msg)
    # Non fare nulla, ma rispondi per chiudere l'indicatore di caricamento
    bot.api.answer_callback_query(callback_query_id: msg.id)
  end

  def self.handle_lista_page(bot, msg, chat_id, user_id, gruppo_id, page, topic_id = 0)
    # Rispondi immediatamente alla callback
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Caricamento pagina #{page + 1}...")

    # 🔥 MODIFICA: Passa topic_id
    success = KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, page, topic_id)

    # Se non è stato possibile aggiornare, rispondi comunque
    unless success
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "Nessun cambiamento necessario",
      )
    end
  end

  def self.handle_cancel_azioni(bot, msg, chat_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "↩️ Tornato alla lista")
    bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
  end

def self.handle_view_foto(bot, msg, chat_id, item_id, gruppo_id, topic_id = 0)
    puts "🔍 [VIEW_FOTO] Richiesta per Item: #{item_id} | Chat: #{chat_id} | Topic: #{topic_id}"

    # Cerchiamo l'immagine e il nome dell'item
    immagine = DB.get_first_row("SELECT file_id FROM item_images WHERE item_id = ?", [item_id])
    item = DB.get_first_row("SELECT nome FROM items WHERE id = ?", [item_id])

    if immagine && immagine["file_id"]
      puts "✅ [VIEW_FOTO] Trovata immagine: #{immagine["file_id"][0..15]}..."

      # Chiude lo spinner del bottone
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "Caricamento foto...")

      # Invia la foto al topic giusto
      bot.api.send_photo(
        chat_id: chat_id,
        photo: immagine["file_id"],
        caption: "📸 Foto per: *#{item ? item["nome"] : "Articolo"}*",
        parse_mode: "Markdown",
        message_thread_id: (chat_id < 0 && topic_id != 0) ? topic_id : nil
      )

      # ✅ Eliminazione automatica del sottomenu (msg.message_id) dopo aver inviato la foto
      begin
        bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
        puts "🧹 [VIEW_FOTO] Sottomenu eliminato correttamente"
      rescue => e
        puts "⚠️ [VIEW_FOTO] Errore pulizia menu: #{e.message}"
      end

    else
      puts "❌ [VIEW_FOTO] Nessuna immagine nel DB per item #{item_id}"
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "⚠️ Nessuna foto trovata",
        show_alert: true,
      )
    end
  rescue => e
    puts "🔥 [VIEW_FOTO] ERRORE: #{e.message}"
    puts e.backtrace.first(3)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Errore visualizzazione")
  end
  
  
  def self.handle_approve_user(bot, msg, chat_id, user_id, username, full_name)
    # ✅ Aggiungi l'utente alla whitelist
    Whitelist.add_user(user_id, username, full_name.gsub("_", " "))
    Whitelist.remove_pending_request(user_id)

    # Conferma al creatore
    bot.api.send_message(
      chat_id: chat_id,
      text: "✅ Utente #{full_name} (@#{username}) approvato e aggiunto alla whitelist.",
    )

    # Notifica all'utente
    bot.api.send_message(
      chat_id: user_id,
      text: "🎉 La tua richiesta di accesso è stata approvata! Ora puoi creare un gruppo con /newgroup.",
    )
  end

  def self.handle_reject_user(bot, msg, chat_id, user_id)
    # ❌ Rimuovi l'utente dai pendenti
    Whitelist.remove_pending_request(user_id)

    # Rispondi alla callback query
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Richiesta rifiutata")

    # Modifica il messaggio originale
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: msg.message.message_id,
      text: "❌ Richiesta rifiutata per ID: #{user_id}",
    )

    # Notifica OPZIONALE all'utente rifiutato
    begin
      bot.api.send_message(
        chat_id: user_id,
        text: "🚫 La tua richiesta di accesso è stata rifiutata dall'amministratore.",
      )
    rescue => e
      puts "⚠️ Impossibile notificare utente rifiutato: #{e.message}"
    end
  end

  def self.handle_show_list(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "📋 Mostro la lista")
    # 🔥 MODIFICA: Passa topic_id
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, nil, 0, topic_id)
  end

def self.handle_add_replace_foto(bot, msg, chat_id, item_id, gruppo_id, topic_id = 0)
    user_id = msg.from.id
    user_name = msg.from.first_name

    puts "📝 [CALLBACK] Imposto pending_action per item #{item_id} nel topic #{topic_id}"

    # Salva l'azione nel database
    DB.execute(
      "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, item_id, initiator_id, topic_id, creato_il) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))",
      [
        chat_id,
        "upload_foto:#{user_name}:#{gruppo_id}:#{item_id}",
        gruppo_id,
        item_id,
        user_id,
        topic_id,
      ]
    )

    # Risponde al callback per togliere lo spinner dal bottone
    bot.api.answer_callback_query(callback_query_id: msg.id)

    # ✅ ELIMINAZIONE SOTTOMENU: Pulizia della chat prima di inviare l'istruzione
    begin
      bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
      puts "🧹 [REPLACE_FOTO] Sottomenu ID #{msg.message.message_id} eliminato"
    rescue => e
      puts "⚠️ [REPLACE_FOTO] Errore pulizia menu: #{e.message}"
    end

    # Invia l'istruzione nel topic corretto
    bot.api.send_message(
      chat_id: chat_id,
      text: "📸 Inviami la foto che vuoi associare a questo articolo...",
message_thread_id: (chat_id < 0 && topic_id != 0) ? topic_id : nil    )
  end
  
  
def self.handle_remove_foto(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    # 1. Rimuoviamo l'immagine dal DB
    Lista.rimuovi_immagine(item_id)
    puts "🗑️ [DB] Record rimosso per item #{item_id}"

    # 2. Verifica di sicurezza: contiamo quante foto restano per quell'item
    # (Dovrebbe essere 0, questo serve a forzare il refresh della lettura DB)
    check = DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = ?", [item_id])
    puts "📊 [CHECK] Foto residue per item #{item_id}: #{check}"

    # 3. Rispondiamo al callback
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "✅ Foto rimossa")

    # 4. Eliminiamo il sottomenu (fondamentale per pulizia)
    begin
      bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
    rescue => e
      puts "⚠️ [REMOVE] Errore delete menu: #{e.message}"
    end

    # 5. AGGIORNAMENTO LISTA: 
    # Usiamo un ID messaggio specifico per la lista principale se lo abbiamo, 
    # altrimenti KeyboardGenerator userà quello del messaggio corrente.
    # IMPORTANTE: KeyboardGenerator deve ricalcolare le icone 📸 basandosi sul DB aggiornato.
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, nil, 0, topic_id)
  end
  
   
  def self.handle_foto_menu(bot, callback, chat_id, item_id, gruppo_id, topic_id = 0)
    has_image = Lista.ha_immagine?(item_id)

# Calcoliamo il thread corretto: 
  # Se la chat_id è > 0 (privata), il thread DEVE essere nil
  thread_corretto = chat_id < 0 ? (topic_id != 0 ? topic_id : nil) : nil
  

    buttons = if has_image
        [
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "👁️ Visualizza foto",
            callback_data: "view_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🔄 Sostituisci foto",
            callback_data: "replace_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🗑️ Rimuovi foto",
            callback_data: "remove_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
        ]
      else
        [
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "📷 Aggiungi foto",
            callback_data: "add_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
          [Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          )],
        ]
      end

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)

    bot.api.send_message(
      chat_id: chat_id,
message_thread_id: thread_corretto, # <-- Qui la correzione
      text: "📸 Gestione foto per l'articolo",
      reply_markup: markup,
    )
  end

  def self.handle_toggle(bot, msg, item_id, gruppo_id, topic_id = 0)
    item = DB.get_first_row("SELECT i.*, u.first_name, u.last_name, un.initials 
                          FROM items i
                          LEFT JOIN user_names u ON i.creato_da = u.user_id
                          LEFT JOIN user_names un ON un.user_id = ?
                          WHERE i.id = ?", [msg.from.id, item_id])

    if item
      # recupero la sigla dell'utente che ha fatto il toggle
      initials = item["initials"] || (item["first_name"]&.chars&.first || "U")
      current = item["comprato"]

      if current.nil? || current.strip == ""
        # non comprato → segno come comprato da questo utente
        DB.execute("UPDATE items SET comprato = ? WHERE id = ?", [initials, item_id])
        status = "✅"
        info = "#{item["nome"]} comprato da #{initials}"

        # AGGIORNA STORICO: incrementa conteggio
        StoricoManager.aggiorna_da_toggle(item["nome"], gruppo_id, 1)
      else
        # già comprato → lo resetto
        DB.execute("UPDATE items SET comprato = NULL WHERE id = ?", [item_id])
        status = "📄"
        info = "#{item["nome"]} di nuovo da comprare"

        # AGGIORNA STORICO: decrementa conteggio
        StoricoManager.aggiorna_da_toggle(item["nome"], gruppo_id, -1)
      end

      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: info,
        show_alert: true,
      )

      # 🔥 MODIFICA: Passa topic_id
      KeyboardGenerator.genera_lista(bot, msg.message.chat.id, gruppo_id, msg.from.id, msg.message.message_id, 0, topic_id)
    else
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "❌ Item non trovato",
      )
    end
  end

  # Nuovo metodo per gestire lo storico articoli
  def self.aggiorna_storico_articolo(nome_articolo, gruppo_id, incremento)
    # Normalizza il nome (lowercase per evitare duplicati)
    nome_normalizzato = nome_articolo.downcase.strip

    # Cerca o crea record storico
    storico = DB.get_first_row(
      "SELECT * FROM storico_articoli WHERE nome = ? AND gruppo_id = ?",
      [nome_normalizzato, gruppo_id]
    )

    if storico
      # Aggiorna record esistente
      nuovo_conteggio = [storico["conteggio"] + incremento, 0].max # non negativo
      DB.execute(
        "UPDATE storico_articoli SET conteggio = ?, ultima_aggiunta = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        [nuovo_conteggio, incremento > 0 ? Time.now.to_s : storico["ultima_aggiunta"], storico["id"]]
      )
    else
      # Crea nuovo record (solo se incremento positivo)
      if incremento > 0
        DB.execute(
          "INSERT INTO storico_articoli (nome, gruppo_id, conteggio, ultima_aggiunta) VALUES (?, ?, ?, ?)",
          [nome_normalizzato, gruppo_id, 1, Time.now.to_s]
        )
      end
    end
  end

  def self.handle_toggle_view_mode(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    new_mode = Preferences.toggle_view_mode(user_id)

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: new_mode == "text_only" ? "📄 Modalità testo" : "📱 Modalità compatta",
    )

    # 🔥 MODIFICA: Passa topic_id
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_aggiungi(bot, msg, chat_id, gruppo_id, topic_id = 0)
    # Se msg proviene da una CallbackQuery, l'utente è in msg.from
    # Se msg è un Message standard, è lo stesso.
    user_id = msg.from.id
    user_name = msg.from.first_name
    action = "add:#{user_name}"

    # 1. Salvataggio Azione Pendente
    begin
      query = "INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id, initiator_id, creato_il) VALUES (?, ?, ?, ?, ?, datetime('now'))"
      DB.execute(query, [chat_id, topic_id, action, gruppo_id, user_id])
      puts "✅ SQL SUCCESS: Azione salvata per il chat #{chat_id} topic #{topic_id}"
    rescue => e
      puts "❌ SQL ERROR: #{e.message}"
    end

    # Rispondi alla callback se è una query per togliere l'orologio dal bottone
    bot.api.answer_callback_query(callback_query_id: msg.id) if msg.respond_to?(:id)

    # 2. Invio istruzioni
    # Recuperiamo il nome del topic per rendere il messaggio più chiaro
    topic_name = DB.get_first_value("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [chat_id, topic_id]) || "questo reparto"
    text = "✍️ <b>#{user_name}</b>, scrivi gli articoli per <b>#{topic_name}</b>:"

    begin
      # Calcolo del thread: se chat_id < 0 (gruppo) e topic_id > 0, lo passiamo.
      # Se siamo in chat privata (chat_id > 0), thread_id deve essere nil.
      target_thread = (chat_id < 0 && topic_id != 0) ? topic_id : nil

      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: target_thread,
        text: text,
        parse_mode: "HTML",
      )
      puts "DEBUG SEND: Istruzioni inviate a chat #{chat_id} (thread: #{target_thread || "0/Privato"})"
    rescue => e
      puts "❌ API ERROR in handle_aggiungi: #{e.message}"
    end
  end

  def self.handle_cancel_foto(bot, callback, chat_id)
    # 1. Recuperiamo i dati del messaggio che contiene il bottone "Annulla"
    msg_id_da_eliminare = callback.message.message_id

    puts "🧹 [DEBUG CANCEL] Il bottone cliccato appartiene al messaggio ID: #{msg_id_da_eliminare}"

    # 2. Chiudiamo l'orologio (spinner) su Telegram
    bot.api.answer_callback_query(callback_query_id: callback.id)

    begin
      # 3. Eliminiamo ESATTAMENTE quel messaggio
      bot.api.delete_message(chat_id: chat_id, message_id: msg_id_da_eliminare)
      puts "🗑️ [DEBUG CANCEL] Eliminazione completata per ID: #{msg_id_da_eliminare}"
    rescue => e
      puts "⚠️ [DEBUG CANCEL] Errore delete: #{e.message}. Provo a editare..."
      # Se non può eliminare, lo "svuota" (fallback)
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: msg_id_da_eliminare,
        text: "❌ Menu chiuso.",
      )
    end
  end

  def self.handle_info(bot, msg, item_id, gruppo_id, topic_id = 0)
    item = Lista.trova(item_id)
    if item
      # Se il campo 'comprato' è vuoto → da comprare, altrimenti contiene la sigla
      stato = item["comprato"].to_s.strip.empty? ? "📄 Da comprare" : "✅ Comprato da #{item["comprato"]}"

      # Mostriamo il nome e lo stato
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "#{item["nome"]} - #{stato}",
        show_alert: true,
      )
    else
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "❌ Articolo non trovato",
      )
    end
  end

  def self.handle_show_checklist(bot, msg, chat_id, user_id, gruppo_id, topic_id)
    # Assicuriamoci che chat_id non sia nullo.
    # Se msg è un callback, il chat_id è in msg.message.chat.id
    id_effettivo_chat = chat_id || (msg.message ? msg.message.chat.id : nil)

    if id_effettivo_chat.nil?
      puts "❌ [ERRORE] Impossibile recuperare chat_id per checklist"
      return
    end

    # Passiamo i dati direttamente a genera_checklist invece di simulare un messaggio
    StoricoManager.genera_checklist(bot, id_effettivo_chat, user_id, gruppo_id, topic_id)

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "📋 Checklist caricata",
    )
  end
  def self.gestisci_chiusura_ui(bot, msg, callback_data)
    if callback_data =~ /^ui_close:(-?\d+):(\d+)$/
      chat_id = $1.to_i
      topic_id = $2.to_i

      puts "🧹 [UI] Chiudi messaggio chat #{chat_id} topic #{topic_id}"

      begin
        bot.api.delete_message(
          chat_id: chat_id,
          message_thread_id: topic_id > 0 ? topic_id : nil,
          message_id: msg.message.message_id,
        )
        bot.api.answer_callback_query(callback_query_id: msg.id)
      rescue => e
        puts "❌ Errore chiusura UI: #{e.message}"
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌")
      end

      return true
    end

    false
  end
end
