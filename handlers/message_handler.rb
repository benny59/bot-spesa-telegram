# handlers/message_handler.rb
require_relative '../models/lista'
require_relative '../models/group_manager'
require_relative '../models/whitelist'  # AGGIUNGI QUESTA LINEA
require_relative '../utils/keyboard_generator'
require_relative '../db'

class MessageHandler
  def self.handle(bot, msg, bot_username)
    chat_id = msg.chat.id
    user_id = msg.from.id if msg.from
    puts "💬 Messaggio: #{msg.text} - Chat: #{chat_id} - Type: #{msg.chat.type}"

    # Salva il nome utente quando ricevi un messaggio
    if msg.from
      GroupManager.salva_nome_utente(msg.from.id, msg.from.first_name, msg.from.last_name)
    end

    # Gestione messaggi con foto (prima di tutto il resto)
    if msg.photo && msg.photo.any?
      handle_photo_message(bot, msg, chat_id, user_id)
      return
    end

    # Gestione messaggi privati
    if msg.chat.type == "private"
      handle_private_message(bot, msg, chat_id, user_id)
      return
    end

    # Gestione messaggi in gruppi
    if msg.chat.type == "group" || msg.chat.type == "supergroup"
      handle_group_message(bot, msg, chat_id, user_id, bot_username)
    end
  end

  private

  def self.handle_photo_message(bot, msg, chat_id, user_id)
    puts "📸 Messaggio foto ricevuto"
    
    # Cerca se c'è un'azione pending per upload foto
    pending = DB.get_first_row("SELECT * FROM pending_actions WHERE chat_id = ? AND action LIKE 'upload_foto%'", [chat_id])
    
    if pending
      # Estrai item_id dall'azione pending
      if pending['action'] =~ /upload_foto:(.+):(\d+):(\d+)/
        item_id = $3.to_i
        gruppo_id = pending['gruppo_id']
        
        # Prendi la foto più grande (ultima nell'array)
        photo = msg.photo.last
        file_id = photo.file_id
        
        # Salva la foto nel database
        DB.execute("INSERT OR REPLACE INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
                  [item_id, file_id, photo.file_unique_id])
        
        # Rimuovi l'azione pending
        DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
        
        bot.api.send_message(
          chat_id: chat_id,
          text: "✅ Foto aggiunta all'articolo!"
        )
        
        # Aggiorna la lista
        KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id)
      end
    else
      puts "📸 Foto ricevuta ma nessuna azione pending trovata"
    end
  end

# handlers/message_handler.rb - modifica handle_private_message
def self.handle_private_message(bot, msg, chat_id, user_id)
  case msg.text
  
  
when '/newgroup'
  # Se whitelist vuota, questo è il primo utente -> diventa creatore
  if Whitelist.get_creator_id.nil?
    Whitelist.add_creator(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")
    puts "🎉 Creatore automatico: #{msg.from.first_name} #{msg.from.last_name} (ID: #{user_id})"
  end

  unless Whitelist.is_allowed?(user_id)
    # Aggiungi alla lista di attesa
    Whitelist.add_pending_request(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")
    
    # Notifica il creatore
    creator_id = Whitelist.get_creator_id
    if creator_id
      bot.api.send_message(
        chat_id: creator_id,
        text: "🔔 *Richiesta di accesso*\\n\\n" \
              "👤 #{msg.from.first_name} #{msg.from.last_name}\\n" \
              "📧 @#{msg.from.username}\\n" \
              "🆔 #{user_id}\\n\\n" \
              "Aggiungere alla whitelist?",
        parse_mode: 'Markdown',
        reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "✅ Approva",
              callback_data: "approve_user:#{user_id}:#{msg.from.username}:#{msg.from.first_name}_#{msg.from.last_name}"
            ),
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Rifiuta", 
              callback_data: "reject_user:#{user_id}"
            )
          ]
        ])
      )
    end

    bot.api.send_message(
      chat_id: chat_id,
      text: "📨 La tua richiesta di accesso è stata inviata all'amministratore. Riceverai una notifica quando verrà approvata."
    )
    return
  end

  # Se arriva qui, l'utente è autorizzato
  result = GroupManager.crea_gruppo(bot, user_id, msg.from.first_name)
  if result[:success]
    bot.api.send_message(chat_id: chat_id, text: "🎉 Gruppo virtuale creato (ID: #{result[:gruppo_id]})\\nAggiungi il bot al gruppo e scrivi /start nel gruppo.")
  else
    bot.api.send_message(chat_id: chat_id, text: "❌ Errore: #{result[:error]}")
  end
  
  when '/whois_creator'
  creator_id = Whitelist.get_creator_id
  if creator_id
    creator = DB.get_first_row("SELECT * FROM whitelist WHERE user_id = ?", [creator_id])
    bot.api.send_message(
      chat_id: chat_id,
      text: "👑 Creatore del bot:\\n👤 #{creator['full_name']}\\n📧 @#{creator['username']}\\n🆔 #{creator['user_id']}"
    )
  else
    bot.api.send_message(chat_id: chat_id, text: "🤷 Nessun creatore impostato ancora.")
  end
  when '/start'
    bot.api.send_message(
      chat_id: chat_id, 
      text: "👋 Benvenuto! Usa /newgroup per creare un gruppo virtuale."
    )
  
  # Aggiungi comandi admin per gestire la whitelist
when '/whitelist_show'
  unless Whitelist.is_creator?(user_id)
    bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può vedere la whitelist.")
    return
  end

  users = Whitelist.all_users
  if users.empty?
    bot.api.send_message(chat_id: chat_id, text: "📋 Whitelist vuota")
  else
    text = "📋 Utenti autorizzati:\n"
    users.each do |user|
      text += "• #{user['full_name']} (@#{user['username'] || 'nessuno'})\n"
    end
    bot.api.send_message(chat_id: chat_id, text: text)
  end

when '/pending_requests'
  unless Whitelist.is_creator?(user_id)
    bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può vedere le richieste pendenti.")
    return
  end

  requests = Whitelist.get_pending_requests
  if requests.empty?
    bot.api.send_message(chat_id: chat_id, text: "📭 Nessuna richiesta pendente.")
  else
    text = "📋 Richieste pendenti:\n\n"
    requests.each do |req|
      text += "👤 #{req['full_name']}\n📧 @#{req['username'] || 'nessuno'}\n🆔 #{req['user_id']}\n\n"
    end
    bot.api.send_message(chat_id: chat_id, text: text)
  end

when '/whitelist_add'
  unless Whitelist.is_creator?(user_id)
    bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può aggiungere utenti.")
    return
  end

  # Logica per aggiungere utenti (se vuoi implementarla)
  bot.api.send_message(chat_id: chat_id, text: "ℹ️ Usa il formato: /whitelist_add <user_id> <nome>")
end
end
# handlers/message_handler.rb - modifica handle_group_message
def self.handle_group_message(bot, msg, chat_id, user_id, bot_username)
  gruppo = GroupManager.get_gruppo_by_chat_id(chat_id)
  return unless gruppo  # Esci se non c'è gruppo associato

  # Gestione comandi /start
  if msg.text == "/start" || msg.text == "/start@#{bot_username}"
    if gruppo.nil?
      GroupManager.associa_gruppo_automaticamente(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo già associato (ID: #{gruppo['id']}). Usa /lista.")
    end
    return
  end

  # Gestione comando /lista
  if msg.text == '/lista' || msg.text == "/lista@#{bot_username}"
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo['id'], user_id)
    return
  end

  # Gestione SOLO se c'è un'azione pending specifica
  handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
end
  def self.handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo
    
    pending = DB.get_first_row("SELECT * FROM pending_actions WHERE chat_id = ?", [chat_id])
    return unless pending && pending['action'].to_s.start_with?('add') && pending['gruppo_id'] == gruppo['id']

    if msg.text == "/annulla"
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
      bot.api.send_message(chat_id: chat_id, text: "❌ Aggiunta annullata")
      return
    end

    if msg.text && !msg.text.start_with?('/')
      Lista.aggiungi(pending['gruppo_id'], user_id, msg.text)
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
      bot.api.send_message(chat_id: chat_id, text: "✅ #{msg.from.first_name} ha aggiunto: #{msg.text}")
      KeyboardGenerator.genera_lista(bot, chat_id, pending['gruppo_id'], user_id)
    end
  end
end
