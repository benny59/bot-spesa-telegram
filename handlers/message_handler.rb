# handlers/message_handler.rb
require_relative "storico_manager"
require_relative "../models/pending_action"
require_relative "../models/context"
require "json"
require_relative "../utils/logger"
require "rmagick"
require "prawn"
require "prawn/table"
require "tempfile"
require "open-uri"
require "time"

class MessageHandler
  def self.route(bot, msg, context)
    Whitelist.ensure_user_name(msg.from.id, msg.from.first_name, msg.from.last_name)
    text = msg.text.to_s.strip

    if msg.photo && msg.photo.any?
      # 1️⃣ prova SEMPRE il flusso legacy con pending_action (gruppo o privato)
      handled = handle_photo_message(bot, msg, context.chat_id, context.user_id)

      return if handled

      # 2️⃣ solo se NON c'è pending_action e siamo in privato → barcode / carte
      if context.scope == :private
        handle_private_photo(bot, msg, context)
      else
        puts "📸 Foto ignorata (nessuna pending_action, scope #{context.scope})"
      end

      return
    end

    case
    when context.private_chat?
      route_private(bot, msg, context)
    when context.group_chat?
      route_group(bot, msg, context)
    else
      log_unhandled(context, "chat_type sconosciuto")
    end
  end

  def self.route_private(bot, msg, context)
    # --- FISSA QUI ---
    chat_id = msg.chat.id
    user_id = msg.from.id
    text = msg.text
    config_row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{context.user_id}"])
    config = config_row ? JSON.parse(config_row["value"]) : nil

    Logger.debug("route_private", user: context.user_id, config: config)

    case msg.text
    
  
when "/private"
  KeyboardGenerator.show_private_keyboard(bot, context.chat_id)
  Context.show_group_selector(bot, context.user_id)
  
when '/setup_pin'
return
  
  when /^🛒 LISTA/
     if config
        # Mostra la lista usando i dati del gruppo selezionato
        puts "DEBUG ACTION: Genero lista per #{config["db_id"]}"
        KeyboardGenerator.genera_lista(
          bot,
          context.chat_id,   # Chat privata
          config["db_id"],   # Gruppo da cui leggere
          context.user_id,
          nil,
          0,
          config["topic_id"], # Filtra per il reparto (es. Topic 2)
          0 # <-- Invia nel thread 0 (cioè nessuno) della chat privata
        )
      else
        bot.api.send_message(chat_id: context.chat_id, text: "❌ Seleziona prima un gruppo con /private")
      end
      
when "➕ AGGIUNGI PRODOTTO"
      CallbackHandler.handle_aggiungi(bot, msg, context.chat_id, context.chat_id,  0)
    when "/newgroup"
      handle_newgroup(bot, msg, chat_id, user_id)
    when "/whitelist_show"
      Whitelist.is_creator?(user_id) ? handle_whitelist_show(bot, chat_id) : invia_errore_admin(bot, chat_id)
    when /^\/whitelist_add\s+(\d+)/
      Whitelist.is_creator?(user_id) ? handle_whitelist_add(bot, chat_id, $1.to_i) : invia_errore_admin(bot, chat_id)
    when /^\/whitelist_remove\s+(\d+)/
      Whitelist.is_creator?(user_id) ? handle_whitelist_remove(bot, chat_id, $1.to_i) : invia_errore_admin(bot, chat_id)
    when "/pending_requests"
      Whitelist.is_creator?(user_id) ? handle_pending_requests(bot, chat_id) : invia_errore_admin(bot, chat_id)
    when /^\/start$/
      handle_start(bot, context)
    when "/private"
      Context.show_group_selector(bot, context.user_id)
    when "/group", "/exit"
      # 1. Cancelliamo la configurazione dal DB
      DB.execute("DELETE FROM config WHERE key = ?", ["context:#{context.user_id}"])

      # 2. Feedback all'utente
      bot.api.send_message(
        chat_id: context.chat_id,
        text: "🔄 <b>Modalità Privata Disattivata</b>\nIl bot non scriverà più nei gruppi per conto tuo. Ora rispondo solo ai comandi locali.",
        parse_mode: "HTML",
      )
      puts "🔓 User #{context.user_id} è tornato in modalità locale"
    when "/carte"
      Logger.info("Comando /carte (privato) ricevuto", user: context.user_id)
      require_relative "../models/carte_fedelta"
      CarteFedelta.show_user_cards(bot, context.user_id)
    when /^\/addcartagruppo/
      gruppo_id = config["db_id"]
      return if gruppo_id.nil?
      current_topic_id = config["topic_id"]

      # Salvataggio azione con topic corrente (importantissimo)
      DB.execute(
        "INSERT INTO pending_actions (chat_id, action, gruppo_id, initiator_id, topic_id) VALUES (?, ?, ?, ?, ?)",
        [context.chat_id, "ADD_CARTA_GRUPPO", gruppo_id, context.user_id, current_topic_id]
      )
      puts "✅ [PA] pending action salvata: gruppo_id=#{gruppo_id} initiator=#{context.user_id} topic=0"

      # Invia l'interfaccia privata all'utente
      CarteFedeltaGruppo.show_add_to_group_interface(bot, context.user_id, gruppo_id)

      # Rispondi nel topic corretto (se esiste)
      thread_id = (context.respond_to?(:topic_id) && context.topic_id.to_i > 0) ? context.topic_id.to_i : nil
    when "?"
      if config
        # Mostra la lista usando i dati del gruppo selezionato
        puts "DEBUG ACTION: Genero lista per #{config["db_id"]}"
        KeyboardGenerator.genera_lista(
          bot,
          context.chat_id,   # Chat privata
          config["db_id"],   # Gruppo da cui leggere
          context.user_id,
          nil,
          0,
          config["topic_id"], # Filtra per il reparto (es. Topic 2)
          0 # <-- Invia nel thread 0 (cioè nessuno) della chat privata
        )
      else
        bot.api.send_message(chat_id: context.chat_id, text: "❌ Seleziona prima un gruppo con /private")
      end
    when /^\+(.+)?/
      if config
        # Gestione aggiunta articoli (usa il metodo che abbiamo creato prima)
        process_private_add(bot, context, config, msg.text[1..].to_s.strip, msg.from.first_name)
      else
        bot.api.send_message(chat_id: context.chat_id, text: "❌ Seleziona prima un gruppo con /private")
      end
    else
      # Gestione delle risposte testuali se c'è un'azione pendente (es. dopo aver premuto + vuoto)
      handle_private_pending(bot, msg, context, config)
    end
  end

  # =============================
  # METODI DI SUPPORTO PRIVATI
  # =============================
  def self.handle_newgroup(bot, msg, chat_id, user_id)
    puts "🔍 /newgroup richiesto da: #{msg.from.first_name} (ID: #{user_id})"

    # Se non c'è ancora un creatore nel DB, il primo che preme /newgroup lo diventa
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
    # Salva la richiesta pendente nel DB
    Whitelist.add_pending_request(user_id, msg.from.username, "#{msg.from.first_name} #{msg.from.last_name}")

    # Notifica al creatore con bottoni Inline per approvazione rapida
    if creator_id
      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "✅ Approva",
              callback_data: "approve_user:#{user_id}:#{msg.from.username}:#{msg.from.first_name}_#{msg.from.last_name}",
            ),
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Rifiuta",
              callback_data: "reject_user:#{user_id}",
            ),
          ],
        ],
      )

      bot.api.send_message(
        chat_id: creator_id,
        text: "🔔 *Richiesta di accesso*\n\n" \
              "👤 #{msg.from.first_name} #{msg.from.last_name}\n" \
              "📧 @#{msg.from.username}\n" \
              "🆔 #{user_id}\n\n" \
              "Aggiungere alla whitelist?",
        parse_mode: "Markdown",
        reply_markup: keyboard,
      )
    end

    bot.api.send_message(
      chat_id: chat_id,
      text: "📨 La tua richiesta di accesso è stata inviata all'amministratore.\nRiceverai una notifica quando verrà approvata.",
    )
  end
  

  def self.handle_newgroup_approved(bot, msg, chat_id, user_id)
    begin
      nome_gruppo = "Lista di #{msg.from.first_name}"

      # Esegui l'inserimento nel DB (Tabella gruppi: id, nome, creato_da, chat_id)
      DB.execute(
        "INSERT INTO gruppi (nome, creato_da, chat_id) VALUES (?, ?, ?)",
        [nome_gruppo, user_id, chat_id]
      )

      # Recupera l'ultimo ID inserito usando il wrapper esistente
      gruppo_id = DB.get_first_value("SELECT last_insert_rowid()")

      bot.api.send_message(
        chat_id: chat_id,
        text: "🎉 *Gruppo virtuale creato!*\n\n" \
              "🆔 ID Interno: `#{gruppo_id}`\n" \
              "👤 Creatore: #{msg.from.first_name}\n\n" \
              "Ora puoi usare i comandi della lista in questa chat.",
        parse_mode: "Markdown",
      )
    rescue => e
      puts "❌ Errore creazione gruppo: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore durante la creazione: #{e.message}")
    end
  end

  # 🔥 NUOVO METODO: Crea la carta dalla foto (gestisce entrambi i casi)
  def self.create_card_from_photo(bot, chat_id, user_id, image_path, nome_carta, codice_carta, formato_originale = nil)
    begin
      # Usa il metodo di CarteFedelta per creare la carta
      CarteFedelta.add_card_from_photo(bot, user_id, nome_carta, codice_carta, image_path, formato_originale)

      # Pulisci l'azione pending se esiste
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
    rescue => e
      puts "❌ Errore creazione carta da foto: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nella creazione della carta dalla foto.")

      # Pulisci comunque l'azione pending
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
    end
  end

  # Cerca la pending action specifica per questo utente
def self.handle_photo_message(bot, msg, chat_id, user_id)
    # 1. Recuperiamo il contesto dal messaggio usando la factory di Context
    ctx = Context.from_message(msg) 
    puts "🔍 [PHOTO_DEBUG] Inizio scansione per user_id: #{user_id} in chat: #{chat_id}"

    # 2. Cerchiamo l'azione pendente (flessibile sul topic per evitare il salto allo 0)
    pending = DB.get_first_row(
      "SELECT * FROM pending_actions 
       WHERE chat_id = ? 
       AND initiator_id = ? 
       AND action LIKE 'upload_foto%' 
       ORDER BY creato_il DESC LIMIT 1",
      [chat_id, user_id]
    )

    unless pending
      puts "ℹ️ [PHOTO_DEBUG] Nessuna pending action trovata per questo utente."
      return false
    end

    puts "📸 [PHOTO_DEBUG] Trovata azione: #{pending["action"]} | Salva su Item: #{pending["item_id"]}"

    # Estrazione dati in sicurezza
    item_id = pending["item_id"]
    gruppo_id = pending["gruppo_id"]
    
    # Recuperiamo il topic originale dal DB (dove abbiamo salvato l'azione)
    # Se nel DB non c'è, usiamo ctx.topic_id come fallback
    target_topic_id = pending["topic_id"] || ctx.topic_id || 0

    # Estraiamo l'oggetto foto correttamente (l'ultima è la risoluzione più alta)
    photo_obj = msg.photo.last
    puts "🖼️ [PHOTO_DEBUG] FileID Telegram: #{photo_obj.file_id[0..15]}..."

    begin
      # 3. Aggiornamento Immagine
      puts "💾 [PHOTO_DEBUG] Esecuzione SQL su item_images..."
      DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id])
      DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
                 [item_id, photo_obj.file_id, photo_obj.file_unique_id])

      # 4. Pulizia Pending Action
      puts "🧹 [PHOTO_DEBUG] Pulizia pending_actions (match su chat/user/item)..."
      DB.execute(
        "DELETE FROM pending_actions 
         WHERE chat_id = ? AND initiator_id = ? AND item_id = ?",
        [chat_id, user_id, item_id]
      )

      # 5. Feedback nel topic corretto (usiamo target_topic_id e logica thread_id)
      puts "📤 [PHOTO_DEBUG] Invio conferma al topic: #{target_topic_id}"
      
      thread_id = (chat_id.to_i < 0 && target_topic_id.to_i != 0) ? target_topic_id.to_i : nil

      bot.api.send_message(
        chat_id: chat_id,
        text: "✅ Foto salvata con successo!",
        message_thread_id: thread_id,
        parse_mode: "Markdown"
      )

      # 6. Refresh della lista (usa genera_lista_compatta se preferisci non inviare la tastiera full)
      puts "🔄 [PHOTO_DEBUG] Generazione lista aggiornata..."
      KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, nil, 0, target_topic_id)

      puts "✨ [PHOTO_DEBUG] Flusso completato con successo."
      return true

    rescue => e
      puts "❌ [PHOTO_DEBUG] CRASH: #{e.message}"
      puts e.backtrace.first(3).join("\n")

      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore durante il salvataggio della foto: #{e.message}",
        message_thread_id: (target_topic_id.to_i != 0 ? target_topic_id.to_i : nil)
      )
      return true
    end
  end
   
 def self.setup_pinned_access(bot, chat_id, gruppo_id, topic_id)
  keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
    inline_keyboard: [[
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🛒 MOSTRA LISTA AGGIORNATA", 
        callback_data: "refresh_lista:#{gruppo_id}:#{topic_id}"
      )
    ]]
  )

  thread_id = (topic_id.to_i > 0) ? topic_id.to_i : nil

  begin
    res = bot.api.send_message(
      chat_id: chat_id,
      message_thread_id: thread_id,
      text: "📌 **Punto di Accesso Rapido**\nUsa il tasto qui sotto per richiamare la lista spesa aggiornata.",
      reply_markup: keyboard,
      parse_mode: "Markdown"
    )

    msg_id = res["result"]["message_id"] rescue res.message_id
    
    begin
      bot.api.pin_chat_message(chat_id: chat_id, message_id: msg_id)
      puts "✅ [SETUP_PIN] Messaggio fissato nel topic #{topic_id}"
    rescue Telegram::Bot::Exceptions::ResponseError => e
      if e.message.include?("not enough rights")
        # Avvisa l'utente nel topic se il bot non è admin
        bot.api.send_message(
          chat_id: chat_id,
          message_thread_id: thread_id,
          text: "⚠️ **Attenzione**: Il messaggio è stato inviato ma non ho i permessi per fissarlo in alto. Aggiungimi come Amministratore con permesso di 'Fissare messaggi'."
        )
      end
      puts "❌ Errore Pin: #{e.message}"
    end
  rescue => e
    puts "❌ Errore Invio: #{e.message}"
  end
end



  def self.handle_photo_with_caption(bot, msg, chat_id, user_id)
    caption = msg.caption.strip
    photo = msg.photo.last

    begin
      # 🔥 MODIFICA: Prima scansiona il barcode, poi chiedi il codice solo se necessario
      file_info = bot.api.get_file(file_id: photo.file_id)
      file_path = file_info.file_path

      if file_path
        # Scarica la foto
        temp_file = Tempfile.new(["barcode_scan", ".jpg"])
        token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")
        file_url = "https://api.telegram.org/file/bot#{token}/#{file_path}"

        puts "📥 Download immagine da: #{file_url}"

        URI.open(file_url) do |remote_file|
          temp_file.write(remote_file.read)
        end
        temp_file.rewind

        # Scansiona barcode
        puts "🔍 Scansionando barcode con zbar..."
        scan_result = BarcodeScanner.scan_image(temp_file.path)

        if scan_result && scan_result[:data]
          barcode_data = scan_result[:data]
          barcode_format = scan_result[:format]

          puts "✅ Barcode rilevato: #{barcode_data} (formato: #{barcode_format})"

          # 🔥 CREA DIRETTAMENTE LA CARTA - nome dal caption, codice dal barcode
          create_card_from_photo(bot, chat_id, user_id, temp_file.path, caption, barcode_data, barcode_format)
        else
          puts "❌ Nessun barcode rilevato"
          # Se non trova barcode, chiede il codice manualmente
          DB.execute(
            "INSERT INTO pending_actions (chat_id, action, item_id, creato_il) VALUES (?, ?, ?, datetime('now'))",
            [chat_id, "naming_card_with_caption:#{caption}", photo.file_id]
          )

          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Nessun codice a barre rilevato.\n\nNome: *#{caption}*\nInvia il *codice* manualmente...",
            parse_mode: "Markdown",
          )
        end

        # Pulisci file temporaneo
        temp_file.close
        temp_file.unlink
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Errore nel download dell'immagine.")
      end
    rescue => e
      puts "❌ Errore gestione foto con caption: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'elaborazione della foto.")
    end
  end

  def self.handle_private_photo(bot, msg, context)
    chat_id = context.chat_id
    user_id = context.user_id

    # 🔥 DEBUG: Vediamo cosa c'è nel messaggio
    puts "🔍 DEBUG - Contenuto messaggio foto:"
    puts "  - Ha caption?: #{!msg.caption.nil?}"
    puts "  - Caption: #{msg.caption.inspect}"
    puts "  - Text: #{msg.text.inspect}"
    puts "  - Chat type: #{msg.chat.type}"
    # 🔥 RIMOSSO: puts "  - Content type: #{msg.content_type}" # Questa riga causa l'errore

    # 🔥 MODIFICA: Supporta entrambi i flussi
    if msg.caption && !msg.caption.empty?
      # NUOVO FLUSSO: Foto con caption - usa caption come nome
      puts "📸 Foto ricevuta con caption: #{msg.caption}"
      handle_photo_with_caption(bot, msg, chat_id, user_id)
      return  # 🔥 IMPORTANTE: esci dal metodo qui
    else
      # VECCHIO FLUSSO: Foto senza caption - scansione barcode automatica
      puts "📸 Foto ricevuta in chat privata - Scansione barcode in corso..."
    end

    begin
      # Scarica la foto
      photo = msg.photo.last
      file_info = bot.api.get_file(file_id: photo.file_id)

      # 🔥 CORREZIONE: file_info è un oggetto, non un Hash
      file_path = file_info.file_path

      if file_path
        # Scarica il file temporaneamente
        temp_file = Tempfile.new(["barcode_scan", ".jpg"])
        token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")
        file_url = "https://api.telegram.org/file/bot#{token}/#{file_path}"

        puts "📥 Download immagine da: #{file_url}"

        URI.open(file_url) do |remote_file|
          temp_file.write(remote_file.read)
        end
        temp_file.rewind

        puts "🔍 Scansionando barcode con zbar..."
        scan_result = BarcodeScanner.scan_image(temp_file.path)

        if scan_result && scan_result[:data]
          barcode_data = scan_result[:data]
          barcode_format = scan_result[:format]

          puts "✅ Barcode rilevato: #{barcode_data} (formato: #{barcode_format})"

          # Salva barcode e formato nel pending action
          action_with_barcode = "naming_card:#{barcode_data}:#{barcode_format}"

          DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action) VALUES (?, ?)",
                     [chat_id, action_with_barcode])

          bot.api.send_message(
            chat_id: chat_id,
            text: "📷 Barcode rilevato!\n\nCodice: `#{barcode_data}`\nTipo: #{barcode_format.upcase}\n\nCome vuoi chiamare questa carta? (es. coop, esselunga, pam...)",
            parse_mode: "Markdown",
          )
        else
          puts "❌ Nessun barcode rilevato"
          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Nessun codice a barre rilevato nell'immagine. Assicurati che:\n• La foto sia nitida\n• Il codice sia ben illuminato\n• Non ci siano riflessi",
          )
        end

        # Pulisci file temporaneo
        temp_file.close
        temp_file.unlink
      else
        puts "❌ file_path non disponibile"
        bot.api.send_message(chat_id: chat_id, text: "❌ Errore nel download dell'immagine.")
      end
    rescue => e
      puts "❌ Errore nella scansione barcode: #{e.message}"
      puts e.backtrace.join("\n")
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore durante la scansione del codice a barre: #{e.message}")
    end
  end

  def self.handle_listagruppi(bot, chat_id, user_id)
    # Controllo sicurezza: solo il creatore vede tutto
    unless Whitelist.get_creator_id.to_i == user_id.to_i
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
      return
    end

    rows = DB.execute("SELECT id, nome, creato_da, chat_id FROM gruppi ORDER BY id ASC")
    if rows.empty?
      bot.api.send_message(chat_id: chat_id, text: "ℹ️ Nessun gruppo registrato.")
      return
    end

    elenco = rows.map do |row|
      "🆔 `#{row["id"]}` | *#{row["nome"]}*\n👤 Creatore: `#{row["creato_da"]}`\n💬 Chat ID: `#{row["chat_id"]}`"
    end.join("\n\n---\n\n")

    bot.api.send_message(chat_id: chat_id, text: "📋 *Gruppi registrati:*\n\n#{elenco}", parse_mode: "Markdown")
  end
  def self.handle_whitelist_show(bot, chat_id)
    utenti = Whitelist.all_users
    if utenti.empty?
      bot.api.send_message(chat_id: chat_id, text: "⚪ La whitelist è vuota.")
    else
      testo = "📋 *Utenti in Whitelist:*\n\n"
      utenti.each do |u|
        testo += "• #{u["full_name"]} (@#{u["username"]}) - ID: `#{u["user_id"]}`\n"
      end
      bot.api.send_message(chat_id: chat_id, text: testo, parse_mode: "Markdown")
    end
  end

  def self.handle_whitelist_add(bot, chat_id, target_user_id)
    # Aggiunge un utente manualmente. Nota: username e full_name sono generici
    # finché l'utente non interagisce col bot.
    Whitelist.add_user(target_user_id, "Utente", "Aggiunto manualmente")
    bot.api.send_message(chat_id: chat_id, text: "✅ Utente `#{target_user_id}` aggiunto alla whitelist.")
  end

  def self.handle_whitelist_remove(bot, chat_id, target_user_id)
    # Rimuove l'utente dalla tabella whitelist
    DB.execute("DELETE FROM whitelist WHERE user_id = ?", [target_user_id])
    bot.api.send_message(chat_id: chat_id, text: "🗑️ Utente `#{target_user_id}` rimosso dalla whitelist.")
  end

  def self.handle_pending_requests(bot, chat_id)
    requests = Whitelist.get_pending_requests
    if requests.empty?
      bot.api.send_message(chat_id: chat_id, text: "Nessuna richiesta in attesa.")
    else
      # Qui potresti generare una tastiera inline per approvare/rifiutare
      testo = "⏳ *Richieste in attesa:*\n\n"
      requests.each { |r| testo += "• #{r["full_name"]} (@#{r["username"]}) ID: `#{r["user_id"]}`\n" }
      bot.api.send_message(chat_id: chat_id, text: testo, parse_mode: "Markdown")
    end
  end

  def self.invia_errore_admin(bot, chat_id)
    bot.api.send_message(chat_id: chat_id, text: "❌ Questo comando è riservato al creatore del bot.")
  end

  def self.handle_plus_in_private(bot, msg, context, gruppo_id, target_topic_id, nome_gruppo)
    raw = msg.text[1..].to_s.strip
    user_name = msg.from.first_name

    if raw.empty?
      # Inizia azione pendente salvando anche il topic
      DB.execute(
        "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
        [context.chat_id, "add:#{user_name}", gruppo_id, target_topic_id]
      )
      bot.api.send_message(chat_id: context.chat_id, text: "📝 [#{nome_gruppo}] Scrivi gli articoli per il topic #{target_topic_id}:")
    else
      # Esegui aggiunta diretta
      process_private_add(bot, context, gruppo_id, target_topic_id, raw, user_name, nome_gruppo)
    end
  end

  # Metodo centralizzato per aggiungere e notificare
  # handlers/message_handler.rb
  def self.process_private_add(bot, context, config, items_text, user_name)
    if items_text.empty?
      # Se ha scritto solo "+", attiviamo la PendingAction
      DB.execute(
        "INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id) VALUES (?, ?, ?, ?)",
        [context.chat_id, 0, "add:#{user_name}", config["db_id"]]
      )
      bot.api.send_message(chat_id: context.chat_id, text: "✍️ Scrivi gli articoli per **#{config["topic_name"]}**:")
    else
      # Aggiunta diretta
      Lista.aggiungi(config["db_id"], context.user_id, items_text, config["topic_id"])

      # NOTIFICA AL GRUPPO (Usando il CHAT_ID negativo)
            Context.notifica_gruppo_se_privato(bot, context.user_id, "🛒 #{user_name} ha aggiunto da privato:\n#{items_text}")
 
      bot.api.send_message(chat_id: context.chat_id, text: "✅ Aggiunto a #{config["topic_name"]}!")
      KeyboardGenerator.genera_lista(bot, context.chat_id, config["db_id"], context.user_id, nil, 0, config["topic_id"])
    end
  end

  def self.handle_private_pending(bot, msg, context, config)
    # 1. Recupera l'azione pendente
    pending = PendingAction.fetch(chat_id: context.chat_id, topic_id: 0)

    if pending && pending["action"].to_s.start_with?("add:") && config && config["db_id"]
      user_name = msg.from.first_name
      items_text = msg.text.strip
      return if items_text.empty?

      # 2. Aggiungi gli articoli al database
      Lista.aggiungi(config["db_id"], context.user_id, items_text, config["topic_id"] || 0)

      # 3. NOTIFICA AL GRUPPO (Questa è la parte che mancava!)
      Context.notifica_gruppo_se_privato(bot, context.user_id, "🛒 #{user_name} ha aggiunto da privato:\n#{items_text}")

      # 4. Pulisci l'azione e conferma all'utente
      PendingAction.clear(chat_id: context.chat_id, topic_id: 0)
      bot.api.send_message(chat_id: context.chat_id, text: "✅ Articoli aggiunti a **#{config["topic_name"]}**!")

      # Aggiorna l'interfaccia privata
      KeyboardGenerator.genera_lista(bot, context.chat_id, config["db_id"], context.user_id, nil, 0, config["topic_id"] || 0)
    else
      log_unhandled(context, "private: #{msg.text}")
    end
  end

  # =============================
  # GROUP / SUPERGROUP
  # =============================
  def self.route_group(bot, msg, context)
    config_row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{context.user_id}"])
    config = config_row ? JSON.parse(config_row["value"]) : nil

    gruppo = GroupManager.get_gruppo_by_chat_id(context.chat_id)

    # --- AUTO-AGGANCIAMENTO ---
    if gruppo.nil?
      puts "📡 Gruppo non trovato nel nuovo DB. Registro chat_id: #{context.chat_id}"
      # Registra il gruppo usando i dati del messaggio corrente
      DB.execute(
        "INSERT OR IGNORE INTO gruppi (nome, chat_id, creato_da) VALUES (?, ?, ?)",
        [msg.chat.title, context.chat_id, msg.from.id]
      )
      # Riprova il recupero dopo l'inserimento
      gruppo = GroupManager.get_gruppo_by_chat_id(context.chat_id)
    end
    # --------------------------

    TopicManager.update_from_msg(msg)
    # estrai sempre user_id e topic_id all'inizio del metodo
    user_id = msg.from&.id
    # usa prima context.topic_id (normalizzato), poi msg.message_thread_id, poi fallback 0
    current_topic_id = (context.respond_to?(:topic_id) && context.topic_id && context.topic_id != 0) ? context.topic_id : (msg.message_thread_id || 0)

    puts "DEBUG MSG: '#{msg.text}' in chat #{context.chat_id} topic #{current_topic_id}"

    case msg.text
    
    when '/setup_pin'
      # Recuperiamo l'ID interno del gruppo dal DB (già caricato all'inizio del metodo)
      gruppo_id = gruppo ? gruppo["id"] : nil

      if gruppo_id
        puts "📍 [SETUP_PIN] Eseguo per Gruppo DB:#{gruppo_id} nel Chat:#{context.chat_id} Topic:#{current_topic_id}"
        
        # Invocazione del metodo di supporto (definiscilo sotto o nella stessa classe)
        self.setup_pinned_access(bot, context.chat_id, gruppo_id, current_topic_id)
        
        # Pulizia: eliminiamo il comando dell'utente per tenere pulito il topic
        bot.api.delete_message(chat_id: context.chat_id, message_id: msg.message_id) rescue nil
      else
        bot.api.send_message(
          chat_id: context.chat_id, 
          text: "⚠️ Errore: Gruppo non registrato.", 
          message_thread_id: (current_topic_id != 0 ? current_topic_id : nil)
        )
      end
      
    
    when /^\/addcartagruppo/
      gruppo_id = gruppo ? gruppo["id"] : nil
      return if gruppo_id.nil?

      # Salvataggio azione con topic corrente (importantissimo)
      DB.execute(
        "INSERT INTO pending_actions (chat_id, action, gruppo_id, initiator_id, topic_id) VALUES (?, ?, ?, ?, ?)",
        [context.chat_id, "ADD_CARTA_GRUPPO", gruppo_id, user_id, current_topic_id]
      )
      puts "✅ [PA] pending action salvata: gruppo_id=#{gruppo_id} initiator=#{user_id} topic=#{current_topic_id}"

      # Invia l'interfaccia privata all'utente
      CarteFedeltaGruppo.show_add_to_group_interface(bot, user_id, gruppo_id)

      # Rispondi nel topic corretto (se esiste)
      thread_id = config["topic_id"]

      begin
        bot.api.send_message(
          chat_id: context.chat_id,
          message_thread_id: thread_id,
          text: "🛒 #{msg.from.first_name}, ti ho scritto in privato!",
        )
      rescue => e
        puts "⚠️ Errore invio notifica topic (addcartagruppo): #{e.message}"
        # fallback: invia senza thread
        begin
          bot.api.send_message(chat_id: context.chat_id, text: "🛒 #{msg.from.first_name}, ti ho scritto in privato!")
        rescue => _;         end
      end
    when %r{^/private(@\w+)?$}
      if gruppo.nil?
        bot.api.send_message(chat_id: context.chat_id, message_thread_id: current_topic_id, text: "⚠️ Errore: non riesco a trovare questo gruppo nel database.")
      else
        Context.activate_private_for_group(bot, msg, gruppo)
      end
    when /^\+(.+)?/
      raw = msg.text[1..].to_s.strip
      if raw.empty?
        PendingAction.start_add(context, gruppo)
        bot.api.send_message(
          chat_id: context.chat_id,
          message_thread_id: current_topic_id,
          text: "✍️ #{msg.from.first_name}, scrivi gli articoli per questo reparto:",
        )
      else
        process_add_items(bot: bot, text: raw, context: context, gruppo: gruppo, msg: msg)
      end
      
      
    when "?"
      KeyboardGenerator.genera_lista(
        bot,
        context.chat_id,
        gruppo["id"],
        context.user_id,
        nil,
        0,
        current_topic_id
      )
    else
      pending = PendingAction.fetch(chat_id: context.chat_id, topic_id: current_topic_id)

      if pending && pending["action"].to_s.start_with?("add:")
        items_text = msg.text.strip
        return if items_text.empty?

        process_add_items(bot: bot, text: items_text, context: context, gruppo: gruppo, msg: msg)
        PendingAction.clear(chat_id: context.chat_id, topic_id: current_topic_id)
      end
    end
  end

  # =============================
  # STUB (volutamente vuoti)
  # =============================
  def self.handle_start(bot, context)
    bot.api.send_message(
      chat_id: context.chat_id,
      text: "👋 Bot avviato",
    )
  end

  def self.process_add_items(bot:, text:, context:, gruppo:, msg:)
    return if text.nil? || text.strip.empty?

    topic_id = context.topic_id || 0
    user_id = context.user_id

    # --- LOG DI DEBUG CORRETTO ---
    # Usiamo 'msg' (il parametro), NON 'context.msg'
    puts "🔍 [DEBUG NOME] Analisi oggetto msg: #{msg.class}"

    if msg.respond_to?(:from) && msg.from
      puts "🔍 [DEBUG NOME] From ID: #{msg.from.id}"
      puts "🔍 [DEBUG NOME] First Name: '#{msg.from.first_name}'"
      user_name = msg.from.first_name
    else
      puts "⚠️ [DEBUG NOME] L'oggetto msg non ha dati validi in .from"
      user_name = "Qualcuno"
    end
    # -------------------------------

    items_text = text.strip
    items = items_text.split(",").map(&:strip).reject(&:empty?)
    return if items.empty?

    # 1. Operazioni DB
    Lista.aggiungi(gruppo["id"], user_id, items_text, topic_id)
    items.each { |art| StoricoManager.aggiorna_da_aggiunta(art, gruppo["id"], topic_id) }

    # 2. Notifica (Usa user_name estratto sopra)
    self.notifica_gruppo(bot, gruppo["chat_id"], topic_id, user_name, items.join(", "))

    # 3. Tastiera
    KeyboardGenerator.genera_lista(bot, context.chat_id, gruppo["id"], user_id, nil, 0, topic_id)
  end

  def self.handle_private_mode(bot, context)
    # TODO: gestione sessione privata
    puts "🔒 PRIVATE MODE richiesto da user #{context.user_id}"
  end

  # handlers/message_handler.rb

  def self.log_unhandled(context, msg)
    # Usa context.scope invece di chat_type
    puts "⚠️ UNHANDLED [#{context.scope}] #{msg}"
  end

  def self.notifica_gruppo(bot, real_chat_id, topic_id, user_name, items_string)
    # Log per vedere cosa arriva al metodo di notifica
    puts "📢 [Notifica] Destinatario: #{real_chat_id}, Nome ricevuto: '#{user_name}'"

    final_name = (user_name.nil? || user_name.empty?) ? "Un Utente" : user_name

    begin
      bot.api.send_message(
        chat_id: real_chat_id,
        message_thread_id: (topic_id.to_i == 0 ? nil : topic_id),
        text: "🛒 <b>#{final_name}</b> ha aggiunto:\n#{items_string}",
        parse_mode: "HTML",
      )
      puts "✅ Notifica inviata con successo"
    rescue => e
      puts "❌ Errore invio notifica: #{e.message}"
    end
  end

  def self.handle_plus_command(bot, msg, chat_id, user_id, gruppo)
    if gruppo.nil?
      bot.api.send_message(chat_id: chat_id, text: "❌ Nessuna lista attiva. Usa /newgroup in chat privata.")
      return
    end

    # MODIFICA: Ottieni il topic_id dal messaggio
    topic_id = msg.message_thread_id || 0

    begin
      text = msg.text.strip

      # Gestione PRIORITARIA di +? (help)
      if text == "+?"
        bot.api.send_message(
          chat_id: chat_id,
          text: "📋 <b>Help comando +</b>\n\n" \
                "• <code>+</code> - Mostra prompt aggiunta articoli\n" \
                "• <code>+ articolo</code> - Aggiungi un articolo\n" \
                "• <code>+ art1, art2, art3</code> - Aggiungi multiple articoli\n" \
                "• <code>+?</code> - Mostra questo help",
          parse_mode: "HTML",
        )
        return
      end

      # Se c'è testo dopo il + (escluso il caso +? già gestito)
      if text.length > 1
        items_text = text[1..-1].strip
        if items_text.empty?
          # Solo + senza testo
          DB.execute(
            "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
            [chat_id, "add:#{msg.from.first_name}", gruppo["id"], topic_id]
          )
          bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
        else
          # + seguito da testo - MODIFICA: Passa topic_id a Lista.aggiungi
          Lista.aggiungi(gruppo["id"], user_id, items_text, topic_id)
          added_items = items_text.split(",").map(&:strip)
          added_count = added_items.count
          added_items.each do |articolo|
            StoricoManager.aggiorna_da_aggiunta(articolo.strip, gruppo["id"], topic_id)
          end

          bot.api.send_message(
            chat_id: chat_id,
            message_thread_id: topic_id,
            text: "✅ #{msg.from.first_name} ha aggiunto #{added_count} articolo(i): #{added_items.join(", ")}",
          )
          # MODIFICA: Aggiorna la lista passando topic_id
          KeyboardGenerator.genera_lista(bot, chat_id, gruppo["id"], user_id, nil, 0, topic_id)
        end
      else
        # Solo +
        DB.execute(
          "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
          [chat_id, "add:#{msg.from.first_name}", gruppo["id"], topic_id]
        )
        bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
      end
    rescue => e
      puts "❌ Errore nel comando +: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "❌ Errore nell'aggiunta degli articoli",
      )
    end
  end
end

class TopicManager
  def self.update_from_msg(msg)
    chat_id = msg.chat.id
    topic_id = msg.message_thread_id || 0
    topic_name = nil

    # Caso 0: Topic Generale (non ha eventi forum_topic_created)
    if topic_id == 0
      # Verifichiamo se esiste già, altrimenti mettiamo il default
      exists = DB.get_first_value("SELECT 1 FROM topics WHERE chat_id = ? AND topic_id = 0", [chat_id])
      topic_name = "Generale" unless exists
      # Caso A: Messaggio di servizio creazione topic (ID > 0)
    elsif msg.forum_topic_created
      topic_name = msg.forum_topic_created.name
      # Caso B: Messaggio di servizio modifica topic
    elsif msg.forum_topic_edited
      topic_name = msg.forum_topic_edited.name
      # Caso C: Metadati nel reply
    elsif msg.respond_to?(:reply_to_message) && msg.reply_to_message&.forum_topic_created
      topic_name = msg.reply_to_message.forum_topic_created.name
    end

    return if topic_name.nil?

    DB.execute(
      "INSERT OR REPLACE INTO topics (chat_id, topic_id, nome) VALUES (?, ?, ?)",
      [chat_id, topic_id, topic_name]
    )
    puts "🏷️ Topic censito: #{topic_name} (ID: #{topic_id})"
  end
end
