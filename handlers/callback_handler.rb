# handlers/callback_handler.rb
require_relative '../models/lista'
require_relative '../models/group_manager'
require_relative '../models/whitelist'
require_relative '../models/preferences'
require_relative '../utils/keyboard_generator'
require_relative '../db'

class CallbackHandler
  def self.handle(bot, msg)
    chat_id = msg.message.respond_to?(:chat) ? msg.message.chat.id : msg.from.id
    user_id = msg.from.id
    data = msg.data.to_s
    puts "🖱 Callback: #{data} - User: #{user_id} - Chat: #{chat_id}"

    case data
    when /^comprato:(\d+):(\d+)$/
      handle_comprato(bot, msg, chat_id, user_id, $1.to_i, $2.to_i)

    when /^cancella:(\d+):(\d+)$/
      handle_cancella(bot, msg, chat_id, user_id, $1.to_i, $2.to_i)

    when /^cancella_tutti:(\d+)$/
      handle_cancella_tutti(bot, msg, chat_id, user_id, $1.to_i)

    when /^azioni_menu:(\d+):(\d+)$/
      handle_azioni_menu(bot, msg, chat_id, user_id, $1.to_i, $2.to_i)

    when /^cancel_azioni:(\d+):(\d+)$/
      handle_cancel_azioni(bot, msg, chat_id)

    when /^view_foto:(\d+):(\d+)$/
      handle_view_foto(bot, msg, chat_id, $1.to_i, $2.to_i)
when /^approve_user:(\d+):([^:]*):(.+)$/
  handle_approve_user(bot, msg, chat_id, $1.to_i, $2, $3)
  
      when /^reject_user:(\d+)$/
      handle_reject_user(bot, msg, chat_id, $1.to_i)

    when /^show_list:(\d+)$/
      handle_show_list(bot, msg, chat_id, user_id, $1.to_i)

    when /^(add_foto|replace_foto):(\d+):(\d+)$/
      handle_add_replace_foto(bot, msg, chat_id, $2.to_i, $3.to_i)

    when /^remove_foto:(\d+):(\d+)$/
      handle_remove_foto(bot, msg, chat_id, user_id, $1.to_i, $2.to_i)

    when /^foto_menu:(\d+):(\d+)$/
      handle_foto_menu(bot, msg, chat_id, $1.to_i, $2.to_i)

    when /^toggle:(\d+):(\d+)$/
      handle_toggle(bot, msg, $1.to_i, $2.to_i)

    when /^toggle_view_mode:(\d+)$/
      handle_toggle_view_mode(bot, msg, chat_id, user_id, $1.to_i)

    when /^aggiungi:(\d+)$/
      handle_aggiungi(bot, msg, chat_id, $1.to_i)

    when /^cancel_foto:(\d+):(\d+)$/
      handle_cancel_foto(bot, msg, chat_id)

    when /^info:(\d+):(\d+)$/
      handle_info(bot, msg, $1.to_i, $2.to_i)

    else
      puts "❌ Callback non riconosciuto: #{data}"
    end
  end

  private

  def self.handle_comprato(bot, msg, chat_id, user_id, item_id, gruppo_id)
    nuovo = Lista.toggle_comprato(gruppo_id, item_id, user_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Stato aggiornato")
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
  end

  def self.handle_cancella(bot, msg, chat_id, user_id, item_id, gruppo_id)
    if Lista.cancella(gruppo_id, item_id, user_id)
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "Elemento cancellato")
      KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
    else
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Non puoi cancellare questo elemento")
    end
  end

def self.handle_cancella_tutti(bot, msg, chat_id, user_id, gruppo_id)
  if Lista.cancella_tutti(gruppo_id, user_id)
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "✅ Articoli comprati rimossi"
    )

    # aggiorna la lista dopo la cancellazione
    KeyboardGenerator.genera_lista(
      bot,
      chat_id,
      gruppo_id,
      user_id,
      msg.message.message_id
    )
  else
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "❌ Solo admin può cancellare tutti"
    )
  end
end

  def self.handle_azioni_menu(bot, msg, chat_id, user_id, item_id, gruppo_id)
    has_image = Lista.ha_immagine?(item_id)
    item = Lista.trova(item_id)
    return unless item

    buttons = []
    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: item['comprato'] == 1 ? "❌ Segna da comprare" : "✅ Segna comprato",
        callback_data: "comprato:#{item_id}:#{gruppo_id}"
      )
    ]

    if has_image
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "👁️ Visualizza foto",
          callback_data: "view_foto:#{item_id}:#{gruppo_id}"
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🔄 Sostituisci",
          callback_data: "replace_foto:#{item_id}:#{gruppo_id}"
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🗑️ Rimuovi", 
          callback_data: "remove_foto:#{item_id}:#{gruppo_id}"
        )
      ]
    else
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📷 Aggiungi foto",
          callback_data: "add_foto:#{item_id}:#{gruppo_id}"
        )
      ]
    end

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "ℹ️ Informazioni",
        callback_data: "toggle:#{item_id}:#{gruppo_id}"
      )
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Cancella articolo",
        callback_data: "cancella:#{item_id}:#{gruppo_id}"
      )
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "↩️ Torna alla lista",
        callback_data: "cancel_azioni:#{item_id}:#{gruppo_id}"
      )
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "⚙️ *Menu azioni:* #{item['nome']}",
      parse_mode: 'Markdown',
      reply_markup: markup
    )
  end

  def self.handle_cancel_azioni(bot, msg, chat_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "↩️ Tornato alla lista")
    bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
  end

  def self.handle_view_foto(bot, msg, chat_id, item_id, gruppo_id)
    immagine = Lista.get_immagine(item_id)
    item = Lista.trova(item_id)
    
    if immagine && item && immagine['file_id']
      caption = "📸 Foto associata all'articolo: \"#{item['nome']}\""
      bot.api.send_photo(chat_id: chat_id, photo: immagine['file_id'], caption: caption)
      
      bot.api.send_message(
        chat_id: chat_id,
        text: "Cosa vuoi fare ora?",
        reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
          [Telegram::Bot::Types::InlineKeyboardButton.new(text: "📋 Torna alla lista", callback_data: "show_list:#{gruppo_id}")]
        ])
      )
    else
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Nessuna foto trovata")
    end
  end

def self.handle_approve_user(bot, msg, chat_id, user_id, username, full_name)
  full_name = full_name.gsub('_', ' ')
  username = nil if username == 'nessuno' || username.empty?
  
  # Usa il metodo CORRETTO: approve_user invece di add_user
  Whitelist.approve_user(user_id, username, full_name)
  Whitelist.remove_pending_request(user_id)
  
  bot.api.answer_callback_query(callback_query_id: msg.id, text: "✅ Utente approvato")
  
  # Messaggio di conferma
  confirmation_text = "✅ *Utente approvato*\\n\\n👤 #{full_name}\\n"
  confirmation_text += "📧 @#{username}\\n" if username && !username.empty?
  confirmation_text += "🆔 #{user_id}"
  
  bot.api.edit_message_text(
    chat_id: chat_id,
    message_id: msg.message.message_id,
    text: confirmation_text,
    parse_mode: 'Markdown'
  )
  
  # Notifica l'utente
  begin
    bot.api.send_message(
      chat_id: user_id,
      text: "🎉 La tua richiesta di accesso è stata approvata! Ora puoi usare /newgroup per creare gruppi."
    )
  rescue => e
    puts "❌ Impossibile notificare l'utente: #{e.message}"
  end
end

  def self.handle_reject_user(bot, msg, chat_id, user_id)
    Whitelist.remove_pending_request(user_id)
    
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Richiesta rifiutata")
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: msg.message.message_id,
      text: "❌ Richiesta rifiutata per ID: #{user_id}"
    )
  end

  def self.handle_show_list(bot, msg, chat_id, user_id, gruppo_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "📋 Mostro la lista")
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id)
  end

  def self.handle_add_replace_foto(bot, msg, chat_id, item_id, gruppo_id)
    DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, item_id) VALUES (?, ?, ?, ?)",
              [chat_id, "upload_foto:#{msg.from.first_name}:#{gruppo_id}:#{item_id}", gruppo_id, item_id])
    
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "📸 Inviami la foto per questo articolo..."
    )
  end

  def self.handle_remove_foto(bot, msg, chat_id, user_id, item_id, gruppo_id)
    Lista.rimuovi_immagine(item_id)
    
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "✅ Foto rimossa"
    )
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
  end

  def self.handle_foto_menu(bot, msg, chat_id, item_id, gruppo_id)
    has_image = Lista.ha_immagine?(item_id)
    
    if has_image
      buttons = [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "👁️ Visualizza foto",
            callback_data: "view_foto:#{item_id}:#{gruppo_id}"
          )
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🔄 Sostituisci foto",
            callback_data: "replace_foto:#{item_id}:#{gruppo_id}"
          )
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🗑️ Rimuovi foto", 
            callback_data: "remove_foto:#{item_id}:#{gruppo_id}"
          )
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}"
          )
        ]
      ]
    else
      buttons = [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "📷 Aggiungi foto",
            callback_data: "add_foto:#{item_id}:#{gruppo_id}"
          )
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}"
          )
        ]
      ]
    end

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
    
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "📸 *Gestione foto per l'articolo*",
      parse_mode: 'Markdown',
      reply_markup: markup
    )
  end

def self.handle_toggle(bot, msg, item_id, gruppo_id)
  item = DB.get_first_row("SELECT i.*, u.first_name, u.last_name, un.initials 
                          FROM items i
                          LEFT JOIN user_names u ON i.creato_da = u.user_id
                          LEFT JOIN user_names un ON un.user_id = ?
                          WHERE i.id = ?", [msg.from.id, item_id])

  if item
    # recupero la sigla dell’utente che ha fatto il toggle
    initials = item['initials'] || (item['first_name']&.chars&.first || "U")
    current = item['comprato']

    if current.nil? || current.strip == ""
      # non comprato → segno come comprato da questo utente
      DB.execute("UPDATE items SET comprato = ? WHERE id = ?", [initials, item_id])
      status = "✅"
      info = "#{item['nome']} comprato da #{initials}"
    else
      # già comprato → lo resetto
      DB.execute("UPDATE items SET comprato = NULL WHERE id = ?", [item_id])
      status = "📄"
      info = "#{item['nome']} di nuovo da comprare"
    end

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: info,
      show_alert: true
    )

    # aggiorno tastiera / vista lista
    KeyboardGenerator.genera_lista(bot, msg.message.chat.id, gruppo_id, msg.from.id, msg.message.message_id)
  else
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "❌ Item non trovato"
    )
  end
end
  def self.handle_toggle_view_mode(bot, msg, chat_id, user_id, gruppo_id)
    new_mode = Preferences.toggle_view_mode(user_id)
    
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: new_mode == 'text_only' ? "📄 Modalità testo" : "📱 Modalità compatta"
    )
    
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id)
  end

  def self.handle_aggiungi(bot, msg, chat_id, gruppo_id)
    DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id) VALUES (?, ?, ?)", 
              [chat_id, "add:#{msg.from.first_name}", gruppo_id])
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
  end

  def self.handle_cancel_foto(bot, msg, chat_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Operazione annullata")
    bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
  end

 def self.handle_info(bot, msg, item_id, gruppo_id)
  item = Lista.trova(item_id)
  if item
    # Se il campo 'comprato' è vuoto → da comprare, altrimenti contiene la sigla
    stato = item['comprato'].to_s.strip.empty? ? "📄 Da comprare" : "✅ Comprato da #{item['comprato']}"
    
    # Mostriamo il nome e lo stato
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "#{item['nome']} - #{stato}",
      show_alert: true
    )
  else
    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "❌ Articolo non trovato"
    )
  end
end

end
