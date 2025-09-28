# handlers/message_handler.rb
require_relative '../models/lista'
require_relative '../models/group_manager'
require_relative '../models/carte_fedelta'

require_relative '../models/whitelist'
require_relative '../models/preferences'
require_relative '../utils/keyboard_generator'
require_relative '../db'
require_relative 'storico_manager'  
require_relative 'cleanup_manager'

require 'rmagick'
require 'prawn'
require 'prawn/table'
require 'tempfile'
require 'open-uri'


class MessageHandler

def self.ensure_group_name(bot, msg, gruppo)
  return unless gruppo && gruppo['id']  # 👉 evita errori se nil

  begin
    # Recupera info chat reali da Telegram
    chat_info = bot.api.get_chat(chat_id: msg.chat.id) rescue nil
    real_name = nil

    if chat_info.is_a?(Hash) && chat_info['result']
      real_name = chat_info['result']['title']
    elsif chat_info.respond_to?(:title)
      real_name = chat_info.title
    end

    if real_name && real_name != gruppo['nome']
      DB.execute("UPDATE gruppi SET nome = ? WHERE id = ?", [real_name, gruppo['id']])
      puts "🔄 Aggiornato nome gruppo: #{gruppo['nome']} → #{real_name}"
      gruppo['nome'] = real_name
    end
  rescue => e
    puts "⚠️ Errore aggiornamento nome gruppo: #{e.message}"
  end
end



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

  # ========================================
  # 📸 FOTO
  # ========================================
  def self.handle_photo_message(bot, msg, chat_id, user_id)
    puts "📸 Messaggio foto ricevuto"
    pending = DB.get_first_row("SELECT * FROM pending_actions WHERE chat_id = ? AND action LIKE 'upload_foto%'", [chat_id])
    if pending
      if pending['action'] =~ /upload_foto:(.+):(\d+):(\d+)/
        item_id = $3.to_i
        gruppo_id = pending['gruppo_id']
        photo = msg.photo.last
        file_id = photo.file_id

        DB.execute("INSERT OR REPLACE INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
                   [item_id, file_id, photo.file_unique_id])
        DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])

        bot.api.send_message(chat_id: chat_id, text: "✅ Foto aggiunta all'articolo!")
        KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id)
      end
    else
      puts "📸 Foto ricevuta ma nessuna azione pending trovata"
    end
  end

  # ========================================
  # 🔑 MESSAGGI PRIVATI
  # ========================================
 def self.handle_private_message(bot, msg, chat_id, user_id)
  case msg.text
  when '/start'            
    handle_start(bot, chat_id)

  when '/newgroup'         
    handle_newgroup(bot, msg, chat_id, user_id)

  when '/whois_creator'    
    handle_whois_creator(bot, chat_id, user_id)

  when '/whitelist_show'   
    if Whitelist.is_creator?(user_id)
      handle_whitelist_show(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
    end

  when '/pending_requests' 
    if Whitelist.is_creator?(user_id)
      handle_pending_requests(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
    end

  when '/whitelist_add'    
    if Whitelist.is_creator?(user_id)
      handle_whitelist_add(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
    end

  when '/listagruppi'      
    if Whitelist.is_creator?(user_id)
      handle_listagruppi(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
    end

  when '/cleanup'          
    if Whitelist.is_creator?(user_id)
      CleanupManager.esegui_cleanup(bot, chat_id, user_id)
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
    end

  when '/carte'
    CarteFedelta.show_user_cards(bot, user_id)

  when /^\/addcarta (.+)/
    CarteFedelta.add_card(bot, user_id, $1)
  end
  end

  def self.handle_start(bot, chat_id)
    bot.api.send_message(chat_id: chat_id, text: "👋 Benvenuto! Usa /newgroup per creare un gruppo virtuale.")
  end

  # ========================================
  # 🆕 CREAZIONE GRUPPO
  # ========================================
  def self.handle_newgroup(bot, msg, chat_id, user_id)
    puts "🔍 /newgroup richiesto da: #{msg.from.first_name} (ID: #{user_id})"

    if Whitelist.get_creator_id.nil?
      puts "🎉 Primo utente - Imposto come creatore"
      Whitelist.add_creator(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")
    end

    creator_id = Whitelist.get_creator_id
    is_allowed = Whitelist.is_allowed?(user_id)
    puts "🔍 Whitelist check - Creatore: #{creator_id}, Utente: #{user_id}, Autorizzato: #{is_allowed}"

    unless is_allowed
      handle_newgroup_pending(bot, msg, chat_id, user_id, creator_id)
      return
    end

    handle_newgroup_approved(bot, msg, chat_id, user_id)
  end

def self.handle_newgroup_pending(bot, msg, chat_id, user_id, creator_id)
  # Salva la richiesta pendente
  Whitelist.add_pending_request(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")

  # Notifica al creatore con bottoni
  if creator_id
    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
      inline_keyboard: [
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
      ]
    )

    bot.api.send_message(
      chat_id: creator_id,
      text: "🔔 *Richiesta di accesso*\n\n" \
            "👤 #{msg.from.first_name} #{msg.from.last_name}\n" \
            "📧 @#{msg.from.username}\n" \
            "🆔 #{user_id}\n\n" \
            "Aggiungere alla whitelist?",
      parse_mode: 'Markdown',
      reply_markup: keyboard
    )
  end

  # Avvisa l’utente
  bot.api.send_message(
    chat_id: chat_id,
    text: "📨 La tua richiesta di accesso è stata inviata all'amministratore.\nRiceverai una notifica quando verrà approvata."
  )
end
  def self.handle_newgroup_approved(bot, msg, chat_id, user_id)
    result = GroupManager.crea_gruppo(bot, user_id, msg.from.first_name)
    if result[:success]
      bot.api.send_message(chat_id: chat_id, text: "🎉 Gruppo virtuale creato! ID: #{result[:gruppo_id]}")
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore: #{result[:error]}")
    end
  end
  
  def self.handle_listagruppi(bot, chat_id, user_id)
  creator_id = Whitelist.get_creator_id
  if creator_id.to_i != user_id.to_i
    bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
    return
  end

  rows = DB.execute("SELECT id, nome, creato_da, chat_id FROM gruppi ORDER BY id ASC")
  if rows.empty?
    bot.api.send_message(chat_id: chat_id, text: "ℹ️ Nessun gruppo registrato.")
    return
  end

  elenco = rows.map do |row|
    "🆔 #{row['id']} | #{row['nome']} | 👤 #{row['creato_da']} | 💬 #{row['chat_id']}"
  end.join("\n")

  bot.api.send_message(chat_id: chat_id, text: "📋 Gruppi registrati:\n#{elenco}")
end
  
  

  # ========================================
  # ❌ CANCELLAZIONE GRUPPO
  # ========================================
def self.handle_delgroup(bot, msg, chat_id, user_id)
  gruppo = GroupManager.find_by_chat_id(chat_id)
  
  if gruppo
    puts "🔍 [DEL] Comando /delgroup ricevuto in chat #{chat_id} da utente #{user_id}"
    puts "🔍 [DEL] Query gruppo trovata: #{gruppo.inspect}"
    
    # 1. PRIMA cancella tutti gli items del gruppo
    items_count = DB.execute("DELETE FROM items WHERE gruppo_id = ?", [gruppo['id']])
    
    # 2. POI cancella il gruppo
    DB.execute("DELETE FROM gruppi WHERE id = ?", [gruppo['id']])
    
    puts "🔍 [DEL] Cancellati #{items_count} items del gruppo #{gruppo['id']}"
    puts "🔍 [DEL] Gruppo #{gruppo['id']} cancellato"
    
    # Verifica che sia stato cancellato
    gruppo_dopo = GroupManager.find_by_chat_id(chat_id)
    puts "🔍 [DEL] Dopo DELETE, record ancora presente? #{gruppo_dopo.inspect}"
    
    bot.api.send_message(chat_id: chat_id, 
      text: "✅ Gruppo e #{items_count} items cancellati completamente.")
  else
    bot.api.send_message(chat_id: chat_id, text: "❌ Nessun gruppo attivo da cancellare.")
  end
end
  # ========================================
  # 👥 MESSAGGI DI GRUPPO
  # ========================================
def self.handle_group_message(bot, msg, chat_id, user_id, bot_username)
  puts "🔍 Gestione messaggio gruppo: #{msg.text}"

  # PRIMA di tutto: verifica se c'è un gruppo in attesa per questo utente
  gruppo_in_attesa = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id IS NULL AND creato_da = ?", [user_id])
  
  if gruppo_in_attesa && !msg.text&.start_with?('/delgroup')
    # 🔄 TROVATO GRUPPO IN ATTESA - Esegui accoppiamento
    DB.execute("UPDATE gruppi SET chat_id = ?, nome = ? WHERE id = ?", 
               [chat_id, msg.chat.title, gruppo_in_attesa['id']])
    
    bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo accoppiato! Benvenuto nel tuo nuovo gruppo della spesa.")
    puts "🎯 Gruppo accoppiato: #{gruppo_in_attesa['id']} → chat_id #{chat_id}"
    
    # Ricarica il gruppo aggiornato
    gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [gruppo_in_attesa['id']])
  else
    # Comportamento normale: cerca gruppo esistente
    gruppo = GroupManager.get_gruppo_by_chat_id(chat_id)
  end

  # Aggiorna il nome reale da Telegram se serve
  ensure_group_name(bot, msg, gruppo)

if gruppo.nil?
  case msg.text
  when '/lista', "/lista@#{bot_username}", '/checklist'
    bot.api.send_message(chat_id: chat_id, text: "📭 Nessuna lista della spesa attiva.\nUsa /newgroup in chat privata per crearne una.")
    return
  when '/ss', "/ss@#{bot_username}"
    bot.api.send_message(chat_id: chat_id, text: "📷 Nessuna lista da visualizzare.")
    return
  when '/delgroup', "/delgroup@#{bot_username}"
    bot.api.send_message(chat_id: chat_id, text: "❌ Nessun gruppo da cancellare.")
    return
when '/newgroup', "/newgroup@#{bot_username}"
  # Cerca gruppo in attesa per questo utente
  gruppo_in_attesa = GroupManager.find_pending_by_user(user_id)
  
  if gruppo_in_attesa
    # Accoppiamento
    GroupManager.update_chat_id(gruppo_in_attesa['id'], chat_id, msg.chat.title)
    bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo accoppiato! Ora puoi usare +articolo per aggiungere elementi.")
  else
    bot.api.send_message(chat_id: chat_id, 
      text: "❌ Nessun gruppo in attesa. Usa /newgroup in chat privata prima.")
  end
  return
    else
    # Per +articolo e altri messaggi - messaggio generico
    if msg.text&.start_with?('+')
      bot.api.send_message(chat_id: chat_id, text: "📭 Crea prima una lista con /newgroup in chat privata")
    end
    return
  end
end


    case msg.text
    when '/start', "/start@#{bot_username}"
      return
    when '/ss', "/ss@#{bot_username}"
      handle_screenshot_command(bot, msg, gruppo)
      return
    when '/checklist', "/checklist@#{bot_username}"
       StoricoManager.genera_checklist(bot, msg, gruppo['id'])
      return
    when '/carte', "/carte@#{bot_username}"
       CarteFedelta.show_user_cards(bot, user_id)
      return
    when '/delgroup', "/delgroup@#{bot_username}"
      handle_delgroup(bot, msg, chat_id, user_id)
      return
    when '/lista', "/lista@#{bot_username}"
      KeyboardGenerator.genera_lista(bot, chat_id, gruppo['id'], user_id)
      return
    when '?'
      handle_question_command(bot, chat_id, user_id, gruppo)
      return
    end

    if msg.text&.start_with?('+')
      handle_plus_command(bot, msg, chat_id, user_id, gruppo)
    else
      handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
    end
  end

  def self.handle_question_command(bot, chat_id, user_id, gruppo)
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo['id'], user_id)
  end


  # Metodo helper per aggiungere articolo dalla checklist (richiama handle_plus_command esistente)


  # ========================================
  # ➕ AGGIUNTA ARTICOLI
  # ========================================
 def self.handle_plus_command(bot, msg, chat_id, user_id, gruppo)
   if gruppo.nil?
    bot.api.send_message(chat_id: chat_id, text: "❌ Nessuna lista attiva. Usa /newgroup in chat privata.")
    return
  end
  begin
    text = msg.text.strip
    
    # Gestione PRIORITARIA di +? (help)
    if text == '+?'
      bot.api.send_message(
        chat_id: chat_id,
        text: "📋 <b>Help comando +</b>\n\n" \
              "• <code>+</code> - Mostra prompt aggiunta articoli\n" \
              "• <code>+ articolo</code> - Aggiungi un articolo\n" \
              "• <code>+ art1, art2, art3</code> - Aggiungi multiple articoli\n" \
              "• <code>+?</code> - Mostra questo help",
        parse_mode: 'HTML'
      )
      return
    end
    
    # Se c'è testo dopo il + (escluso il caso +? già gestito)
    if text.length > 1
      items_text = text[1..-1].strip
      if items_text.empty?
        # Solo + senza testo
        DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id) VALUES (?, ?, ?)", 
                  [chat_id, "add:#{msg.from.first_name}", gruppo['id']])
        bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
      else
        # + seguito da testo
        Lista.aggiungi(gruppo['id'], user_id, items_text)
        added_items = items_text.split(',').map(&:strip)
        added_count = added_items.count
        added_items.each do |articolo|
            StoricoManager.aggiorna_da_aggiunta(articolo.strip, gruppo['id'])
        end
        bot.api.send_message(
          chat_id: chat_id,
          text: "✅ #{msg.from.first_name} ha aggiunto #{added_count} articolo(i): #{added_items.join(', ')}"
        )
        KeyboardGenerator.genera_lista(bot, chat_id, gruppo['id'], user_id)
      end
    else
      # Solo +
      DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id) VALUES (?, ?, ?)", 
                [chat_id, "add:#{msg.from.first_name}", gruppo['id']])
      bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
    end
  rescue => e
    puts "❌ Errore nel comando +: #{e.message}"
    bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'aggiunta degli articoli")
  end
end
  # ========================================
  # PENDING ACTIONS
  # ========================================
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
      added_items = msg.text.split(',').map(&:strip)  # ← DEFINISCI added_items QUI
      added_items.each do |articolo|
      nome_normalizzato = articolo.strip.capitalize
      StoricoManager.aggiorna_da_aggiunta(nome_normalizzato, gruppo['id'])
    end
 
      
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
      bot.api.send_message(chat_id: chat_id, text: "✅ #{msg.from.first_name} ha aggiunto: #{msg.text}")
      KeyboardGenerator.genera_lista(bot, chat_id, pending['gruppo_id'], user_id)
    end
  end
  
# Helper: trova un TTF disponibile su Android/Termux
def self.find_ttf_font_path
  candidates = [
    '/system/fonts/DroidSans.ttf',
    '/system/fonts/DroidSans-Regular.ttf',
    '/system/fonts/Roboto-Regular.ttf',
    '/system/fonts/NotoSans-Regular.ttf',
    '/system/fonts/DejaVuSans.ttf',
    '/system/fonts/Arial.ttf'
  ]
  candidates.find { |p| File.exist?(p) }
end

def self.sanitize_pdf_text(str)
  return '' if str.nil?
  s = str.to_s.dup
  # rimuovi i controlli ASCII
  s.gsub!(/[\u0000-\u001F]/, '')
  # sostituisci sequenze invalide/undef con vuoto
  s = s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
  # rimuovi larghe famiglie emoji (opzionale)
  s.gsub(/[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, '')
end


def self.handle_screenshot_command(bot, msg, gruppo)
  begin
    items = Lista.tutti(gruppo['id'])

    if items.nil? || items.empty?
      bot.api.send_message(chat_id: msg.chat.id, text: "📝 La lista è vuota! Non c'è nulla da condividere.")
      return
    end

    filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.pdf"
    font_path = find_ttf_font_path

    Prawn::Document.generate(filename) do |pdf|
      # Se troviamo un TTF, registralo e usalo (per UTF-8)
      if font_path
        pdf.font_families.update(
          "CustomFont" => {
            normal: font_path,
            bold: font_path,
            italic: font_path,
            bold_italic: font_path
          }
        )
        pdf.font "CustomFont"
      else
        # fallback: usa Helvetica, ma così rischiamo la limitazione Windows-1252
        pdf.font "Helvetica" rescue nil
      end

      # Proviamo ad aggiungere il logo del gruppo (se disponibile)
      begin
        chat_info = bot.api.get_chat(chat_id: msg.chat.id) rescue nil
        photo_file_id = nil

        if chat_info.is_a?(Hash)
          # formato: { 'ok' => true, 'result' => {...} }
          res = chat_info['result'] || chat_info
          if res && res['photo']
            photo = res['photo']
            photo_file_id = photo['big_file_id'] || photo['small_file_id'] || photo['big_file_unique_id']
          end
          
        elsif chat_info.respond_to?(:photo) && chat_info.photo
          # oggetto tipizzato (Telegram::Bot::Types::Chat / ChatFullInfo)
          photo = chat_info.photo
          photo_file_id = photo.respond_to?(:big_file_id) ? photo.big_file_id : nil
        end

        if photo_file_id
          file_info = bot.api.get_file(file_id: photo_file_id) rescue nil
          file_path = nil
          if file_info.is_a?(Hash) && file_info['result']
            file_path = file_info['result']['file_path']
          elsif file_info.respond_to?(:file_path)
            file_path = file_info.file_path rescue nil
          end

          if file_path
            token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")
            if token && token.to_s.strip != ''
              file_url = "https://api.telegram.org/file/bot#{token}/#{file_path}"
              Tempfile.create(['group_logo', '.jpg']) do |tmp|
                URI.open(file_url) { |remote| tmp.write(remote.read) }
                tmp.rewind
                pdf.image tmp.path, width: 50, height: 50, position: :left
              end
            end
          end
        end
      rescue => e
        puts "⚠️ Impossibile caricare logo gruppo: #{e.message}"
        # non fermare la generazione del PDF
      end

      # Intestazione
      header_text = sanitize_pdf_text("LISTA DELLA SPESA - #{gruppo['nome']}")
      pdf.move_down 6
      pdf.text header_text, size: 18, style: :bold, align: :center
      pdf.move_down 8
      pdf.stroke_horizontal_rule
      pdf.move_down 12

      # Tabella items
      table_data = [["Stato", "Articolo", "Aggiunto da"]]
      items.each do |it|
        #status = it['comprato'] == 1 ? "[X]" : "[ ]"
        status = it['comprato'] && !it['comprato'].empty? ? " [X](#{it['comprato']})" : "[ ]"
        nome = sanitize_pdf_text(it['nome'])
        initials = sanitize_pdf_text(it['user_initials'] || '')
        table_data << [status, nome, initials]
      end

      pdf.table(table_data, header: true, width: pdf.bounds.width) do |t|
        t.row(0).font_style = :bold
        t.row(0).background_color = "F0F0F0"
        t.columns(0).align = :center
        t.columns(2).align = :center
        t.cells.style(padding: [6, 8, 6, 8])
      end

      pdf.move_down 12
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.text "Aggiornato: #{Time.now.strftime('%d/%m/%Y %H:%M')}", size: 9, align: :center
    end

    # invio file
    bot.api.send_document(
      chat_id: msg.chat.id,
      document: Faraday::UploadIO.new(filename, 'application/pdf'),
      caption: "📋 Lista in PDF - Condividi su WhatsApp, email o stampa!"
    )

  rescue => e
    puts "❌ Errore generazione PDF: #{e.message}"
    puts e.backtrace.join("\n")
    puts "📋 Fallback a formato testo..."
    # usa il fallback testuale (qui passi l'array items per evitare nuova query)
    handle_screenshot_text_fallback(bot, msg.chat.id, gruppo, items)
  ensure
    # pulizia
    File.delete(filename) if filename && File.exist?(filename)
  end
end

# Fallback testuale migliorato (usa items se già forniti)
def self.handle_screenshot_text_fallback(bot, chat_id, gruppo, items = nil)
  begin
    items ||= Lista.tutti(gruppo['id'])
    if items.nil? || items.empty?
      bot.api.send_message(chat_id: chat_id, text: "📝 La lista è vuota!")
      return
    end

    comprati = items.count { |i| i['comprato'] == 1 }
    totali = items.size

    text_response = "*LISTA DELLA SPESA* — #{sanitize_pdf_text(gruppo['nome'])}\n"
    text_response += "_Completati: #{comprati}/#{totali}_\n\n"
    items.each do |it|
      stato = it['comprato'] == 1 ? "[X]" : "[ ]"
      line = "#{stato} #{sanitize_pdf_text(it['nome'])}"
      line += " — #{sanitize_pdf_text(it['user_initials']||'')}" unless (it['user_initials'].nil? || it['user_initials'].strip.empty?)
      text_response += "#{line}\n"
    end
    text_response += "\n_Invio in formato testo a causa di un errore nella generazione PDF_"

    bot.api.send_message(chat_id: chat_id, text: text_response, parse_mode: 'Markdown')
  rescue => e
    puts "❌ Errore anche nel fallback testo: #{e.message}"
    bot.api.send_message(chat_id: chat_id, text: "❌ Errore nel generare la lista. Riprova più tardi.")
  end
end

def self.list_available_fonts
  font_dirs = [
    "/system/fonts",
    "/data/data/com.termux/files/usr/share/fonts",
    "/usr/share/fonts"
  ]
  
  puts "🔍 Cercando font disponibili..."
  
  font_dirs.each do |dir|
    if Dir.exist?(dir)
      puts "📁 Directory: #{dir}"
      fonts = Dir.glob("#{dir}/**/*.ttf").take(10) # Prendi primi 10 per non inondare il log
      fonts.each { |font| puts "   📄 #{File.basename(font)}" }
    end
  end
end




  def self.handle_screenshot_command_old1(bot, msg, gruppo)
    begin
      items = Lista.tutti(gruppo['id'])
      
      if items.empty?
        bot.api.send_message(
          chat_id: msg.chat.id,
          text: "📝 La lista è vuota! Non c'è nulla da condividere."
        )
        return
      end

      # Crea file di testo semplice
      file_content = "🛒 LISTA DELLA SPESA 🛒\n\n"
      
      items.each do |item|
        status = item['comprato'] == 1 ? "[✓]" : "[ ]"
        user_badge = item['user_initials'] ? "#{item['user_initials']}-" : ""
        file_content += "#{status} #{user_badge}#{item['nome']}\n"
      end
      
      file_content += "\nAggiornato: #{Time.now.strftime('%d/%m/%Y %H:%M')}"
      file_content += "\nGenerato da @hassMB_bot"
      
      # Salva come file .txt
      filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.txt"
      File.write(filename, file_content)
      
      # Invia come file
      bot.api.send_document(
        chat_id: msg.chat.id,
        document: Faraday::UploadIO.new(filename, 'text/plain'),
        caption: "📋 Clicca sul file e scegli 'Condividi' per inviare via WhatsApp, Email, ecc."
      )
      
      # Pulisci
      File.delete(filename) if File.exist?(filename)
      
    rescue => e
      puts "❌ Errore generazione screenshot: #{e.message}"
      # Fallback a messaggio semplice
      bot.api.send_message(
        chat_id: msg.chat.id,
        text: "❌ Impossibile generare il file. Usa /lista per vedere la lista."
      )
    end
  end

end
