# handlers/message_handler.rb
require_relative '../models/lista'
require_relative '../models/group_manager'
require_relative '../models/whitelist'
require_relative '../models/preferences'
require_relative '../utils/keyboard_generator'
require_relative '../db'
require 'rmagick'


class MessageHandler
  def self.handle(bot, msg, bot_username)
    chat_id = msg.chat.id
    user_id = msg.from.id if msg.from
    puts "💬 Messaggio: #{msg.text} - Chat: #{chat_id} - Type: #{msg.chat.type}"

    # Salva il nome utente quando ricevi un messaggio
    if msg.from
      Whitelist.salva_nome_utente(msg.from.id, msg.from.first_name, msg.from.last_name)
    end

    if msg.photo && msg.photo.any?
      handle_photo_message(bot, msg, chat_id, user_id)
      return
    end

    if msg.chat.type == "private"
      handle_private_message(bot, msg, chat_id, user_id)
      return
    end

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

  def self.handle_private_message(bot, msg, chat_id, user_id)
    case msg.text
    when '/start'
      handle_start(bot, chat_id)
      
    when '/newgroup'
      handle_newgroup(bot, msg, chat_id, user_id)
      
    when '/whois_creator'
      handle_whois_creator(bot, chat_id, user_id)
      
    when '/whitelist_show'
      handle_whitelist_show(bot, chat_id, user_id)
      
    when '/pending_requests'
      handle_pending_requests(bot, chat_id, user_id)
      
    when '/whitelist_add'
      handle_whitelist_add(bot, chat_id, user_id)
    end
  end

  def self.handle_start(bot, chat_id)
    bot.api.send_message(
      chat_id: chat_id, 
      text: "👋 Benvenuto! Usa /newgroup per creare un gruppo virtuale."
    )
  end

  def self.handle_newgroup(bot, msg, chat_id, user_id)
    puts "🔍 /newgroup richiesto da: #{msg.from.first_name} (ID: #{user_id})"
    
    # Se whitelist vuota, questo è il primo utente -> diventa creatore
    if Whitelist.get_creator_id.nil?
      puts "🎉 Primo utente - Imposto come creatore"
      Whitelist.add_creator(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")
      puts "✅ Creatore automatico: #{msg.from.first_name} #{msg.from.last_name} (ID: #{user_id})"
    end

    # Debug: verifica stato whitelist
    creator_id = Whitelist.get_creator_id
    is_allowed = Whitelist.is_allowed?(user_id)
    puts "🔍 Whitelist check - Creatore: #{creator_id}, Utente: #{user_id}, Autorizzato: #{is_allowed}"

    unless is_allowed
      handle_newgroup_pending(bot, msg, chat_id, user_id, creator_id)
      return
    end

    # Se arriva qui, l'utente è autorizzato
    handle_newgroup_approved(bot, msg, chat_id, user_id)
  end

  def self.handle_newgroup_pending(bot, msg, chat_id, user_id, creator_id)
    puts "🔍 Utente non autorizzato - Aggiungo richiesta pendente"
    # Aggiungi alla lista di attesa
    Whitelist.add_pending_request(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")
    
    # Notifica il creatore
    if creator_id
      puts "🔍 Notifico creatore: #{creator_id}"
      begin
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
      rescue => e
        puts "❌ Errore notifica creatore: #{e.message}"
      end
    else
      puts "❌ Nessun creatore trovato per notifica"
    end

    bot.api.send_message(
      chat_id: chat_id,
      text: "📨 La tua richiesta di accesso è stata inviata all'amministratore. Riceverai una notifica quando verrà approvata."
    )
  end

def self.handle_newgroup_approved(bot, msg, chat_id, user_id)
  puts "🔍 Utente autorizzato - Creo gruppo"
  result = GroupManager.crea_gruppo(bot, user_id, msg.from.first_name)
  
  if result[:success]
    puts "✅ Gruppo creato con ID: #{result[:gruppo_id]}"
    bot.api.send_message(
      chat_id: chat_id, 
      text: "🎉 <b>Gruppo virtuale creato!</b> (ID: <code>#{result[:gruppo_id]}</code>)\n\n" \
            "📋 <b>Istruzioni completamento:</b>\n" \
            "1. Aggiungi @hassMB_bot al gruppo Telegram\n" \
            "2. Scrivi <code>/start</code> nel gruppo\n" \
            "3. Usa <code>/lista</code> per gestire la spesa\n\n" \
            "🔒 Il gruppo sarà attivo dopo l'associazione.",
      parse_mode: 'HTML'
    )
  else
    puts "❌ Errore creazione gruppo: #{result[:error]}"
    bot.api.send_message(
      chat_id: chat_id, 
      text: "❌ Errore nella creazione del gruppo: #{result[:error]}\nRiprova più tardi.",
      parse_mode: 'HTML'
    )
  end
end
#--------------------------------
def self.handle_screenshot_command(bot, msg, gruppo)
  begin
    require 'rmagick'
    
    items = Lista.tutti(gruppo['id'])
    
    # Se la lista è vuota, manda un messaggio
    if items.empty?
      bot.api.send_message(
        chat_id: msg.chat.id,
        text: "📝 La lista è vuota! Non c'è nulla da condividere."
      )
      return
    end

    # Dimensioni immagine
    width = 800
    line_height = 40
    padding = 30
    title_height = 80
    height = padding * 2 + title_height + (items.size * line_height) + 60
    
    # Crea immagine
    image = Magick::Image.new(width, height) do |options|
      options.background_color = 'white'
    end
    
    draw = Magick::Draw.new
    draw.gravity = Magick::NorthWestGravity
    
    # Prova diversi font
    font = find_available_font
    draw.font = font
    
    # Disegna titolo
    draw.fill('black')
    draw.pointsize = 32
    draw.font_weight = Magick::BoldWeight
    draw.annotate(image, 0, 0, padding, padding, "🛒 LISTA DELLA SPESA")
    
    # Linea separatrice
    draw.line(padding, padding + 50, width - padding, padding + 50)
    
    # Disegna items
    draw.pointsize = 20
    draw.font_weight = Magick::NormalWeight
    y_position = padding + title_height
    
    items.each do |item|
      status = item['comprato'] == 1 ? "✅" : "🛒"
      user_badge = item['user_initials'] ? "#{item['user_initials']}-" : "??-"
      text = "#{status} #{user_badge}#{item['nome']}"
      
      # Colore per item completati
      if item['comprato'] == 1
        draw.fill('#888888') # Grigio
      else
        draw.fill('#2c3e50') # Blu scuro
      end
      
      draw.annotate(image, 0, 0, padding, y_position, text)
      y_position += line_height
    end
    
    # Footer
    draw.pointsize = 14
    draw.fill('#7f8c8d') # Grigio medio
    footer_text = "🔄 Aggiornato: #{Time.now.strftime('%d/%m/%Y %H:%M')}"
    draw.annotate(image, 0, 0, padding, height - 50, footer_text)
    
    # Applica il disegno
    draw.draw(image)
    
    # Salva immagine
    filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.png"
    image.write(filename)
    
    # Invia l'immagine
    bot.api.send_photo(
      chat_id: msg.chat.id,
      photo: Faraday::UploadIO.new(filename, 'image/png'),
      caption: "📸 Clicca sull'immagine e scegli 'Condividi' per inviare via WhatsApp, Email, ecc."
    )
    
    # Pulisci
    image.destroy!
    File.delete(filename) if File.exist?(filename)
    
  rescue => e
    puts "❌ Errore generazione immagine: #{e.message}"
    puts e.backtrace
    handle_screenshot_text_fallback(bot, msg.chat.id, gruppo)
  end
end

# Metodo helper per trovare font disponibili
def self.find_available_font
  # Font comuni su Android
  fonts_to_try = [
    'DroidSans',
    'Roboto',
    'NotoSans',
    'sans-serif',
    'arial',
    'helvetica'
  ]
  
  # Cerca il primo font disponibile
  available_fonts = Magick.fonts.map(&:name)
  fonts_to_try.each do |font|
    return font if available_fonts.include?(font)
  end
  
  'fixed' # Fallback
end
  def self.handle_screenshot_text_fallback(bot, chat_id, gruppo)
    begin
      items = Lista.tutti(gruppo['id'])
      file_content = "🛒 LISTA DELLA SPESA 🛒\n\n"

      if items.empty?
        file_content += "La lista è vuota!\n"
      else
        items.each do |item|
          status = item['comprato'] == 1 ? "✅" : "⭕"
          user_badge = item['user_initials'] ? "#{item['user_initials']}-" : ""
          file_content += "#{status} #{user_badge}#{item['nome']}\n"
        end
      end

      file_content += "\nAggiornato: #{Time.now.strftime('%d/%m/%Y %H:%M')}"
      filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.txt"
      File.write(filename, file_content)

      bot.api.send_document(
        chat_id: chat_id,
        document: Faraday::UploadIO.new(filename, 'text/plain'),
        caption: "📋 Clicca sul file e scegli 'Condividi'"
      )
      File.delete(filename) if File.exist?(filename)
    rescue => e
      puts "❌ Errore anche nel fallback: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Impossibile generare l'immagine. Usa /lista per vedere la lista."
      )
    end
  end

def self.handle_screenshot_text_fallback(bot, chat_id, gruppo)
  begin
    items = Lista.tutti(gruppo['id'])
    
    # Crea file di testo come fallback
    file_content = "🛒 LISTA DELLA SPESA 🛒\n\n"
    
    if items.empty?
      file_content += "La lista è vuota!\n"
    else
      items.each do |item|
        status = item['comprato'] == 1 ? "✅" : "⭕"
        user_badge = item['user_initials'] ? "#{item['user_initials']}-" : ""
        file_content += "#{status} #{user_badge}#{item['nome']}\n"
      end
    end
    
    file_content += "\nAggiornato: #{Time.now.strftime('%d/%m/%Y %H:%M')}"
    
    filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.txt"
    File.write(filename, file_content)
    
    bot.api.send_document(
      chat_id: chat_id,
      document: Faraday::UploadIO.new(filename, 'text/plain'),
      caption: "📋 Clicca sul file e scegli 'Condividi'"
    )
    
    File.delete(filename) if File.exist?(filename)
    
  rescue => e
    puts "❌ Errore anche nel fallback: #{e.message}"
    # Ultimo fallback: messaggio semplice
    bot.api.send_message(
      chat_id: chat_id,
      text: "❌ Impossibile generare l'immagine. Usa /lista per vedere la lista."
    )
  end
end
#--------------------------------


  def self.handle_whois_creator(bot, chat_id, user_id)
    creator_id = Whitelist.get_creator_id
    if creator_id
      creator = DB.get_first_row("SELECT * FROM whitelist WHERE user_id = ?", [creator_id])
      is_creator = (user_id == creator_id)
      
      if is_creator
        bot.api.send_message(
          chat_id: chat_id,
          text: "👑 Tu sei il creatore!\\n👤 #{creator['full_name']}\\n📧 @#{creator['username']}\\n🆔 #{creator['user_id']}"
        )
      else
        bot.api.send_message(
          chat_id: chat_id,
          text: "👑 Creatore del bot:\\n👤 #{creator['full_name']}\\n📧 @#{creator['username']}\\n🆔 #{creator['user_id']}"
        )
      end
    else
      bot.api.send_message(chat_id: chat_id, text: "🤷 Nessun creatore impostato ancora.")
    end
  end

  def self.handle_whitelist_show(bot, chat_id, user_id)
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
  end

  def self.handle_pending_requests(bot, chat_id, user_id)
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
  end

  def self.handle_whitelist_add(bot, chat_id, user_id)
    unless Whitelist.is_creator?(user_id)
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può aggiungere utenti.")
      return
    end

    bot.api.send_message(chat_id: chat_id, text: "ℹ️ Usa il formato: /whitelist_add <user_id> <nome>")
  end




# handlers/message_handler.rb - modifica handle_group_message
 def self.handle_group_message(bot, msg, chat_id, user_id, bot_username)
    puts "🔍 Gestione messaggio gruppo: #{msg.text}"
    gruppo = GroupManager.get_gruppo_by_chat_id(chat_id)
    puts "🔍 Gruppo trovato: #{gruppo.inspect}"

    if msg.text == "/start" || msg.text == "/start@#{bot_username}"
      # ...
      return
    end

    unless gruppo
      puts "❌ Nessun gruppo associato a questa chat"
      return
    end

    # ✅ FIX: chiamata con firma giusta
    if msg.text == '/ss' || msg.text == "/ss@#{bot_username}"
      puts "🔍 Comando /ss ricevuto"
      handle_screenshot_command(bot, msg, gruppo)
      return
    end

    if msg.text == '/lista' || msg.text == "/lista@#{bot_username}"
      # ...
      return
    end

    if msg.text&.strip == '?'
      handle_question_command(bot, chat_id, user_id, gruppo)
      return
    end

    if msg.text&.start_with?('+')
      handle_plus_command(bot, msg, chat_id, user_id, gruppo)
      return
    end

    handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
  end

def self.handle_question_command(bot, chat_id, user_id, gruppo)
  KeyboardGenerator.genera_lista(bot, chat_id, gruppo['id'], user_id)
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
