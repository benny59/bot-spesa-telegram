# handlers/message_handler.rb
require_relative "../models/lista"
require_relative "../models/group_manager"
require_relative "../models/carte_fedelta"
require_relative "../models/barcode_scanner"

require_relative "../models/whitelist"
require_relative "../models/preferences"
require_relative "../utils/keyboard_generator"
require_relative "../db"
require_relative "storico_manager"
require_relative "cleanup_manager"

require "rmagick"
require "prawn"
require "prawn/table"
require "tempfile"
require "open-uri"
require "time"  # aggiungi in cima al file se non presente
ITEMS_PER_PAGE = 3  # Numero di gruppi per pagina
GROUPS_PER_PAGE = 2  # Numero di gruppi per pagina

class MessageHandler
  def self.ensure_group_name(bot, msg, gruppo)
    return unless gruppo && gruppo["id"]  # 👉 evita errori se nil

    begin
      # Recupera info chat reali da Telegram
      chat_info = bot.api.get_chat(chat_id: msg.chat.id) rescue nil
      real_name = nil

      if chat_info.is_a?(Hash) && chat_info["result"]
        real_name = chat_info["result"]["title"]
      elsif chat_info.respond_to?(:title)
        real_name = chat_info.title
      end

      if real_name && real_name != gruppo["nome"]
        DB.execute("UPDATE gruppi SET nome = ? WHERE id = ?", [real_name, gruppo["id"]])
        puts "🔄 Aggiornato nome gruppo: #{gruppo["nome"]} → #{real_name}"
        gruppo["nome"] = real_name
      end
    rescue => e
      puts "⚠️ Errore aggiornamento nome gruppo: #{e.message}"
    end
  end

  def self.handle(bot, msg, bot_username)
    chat_id = msg.chat.id
    user_id = msg.from.id if msg.from
    puts "💬 Messaggio: #{msg.text} - Chat: #{chat_id} - Type: #{msg.chat.type}"

    if msg.photo
      puts "📸 MESSAGGIO FOTO RILEVATO:"
      puts "  - Caption: #{msg.caption.inspect}"
      puts "  - Text: #{msg.text.inspect}"
      puts "  - Numero foto: #{msg.photo.size}"
    end

    # Salva il nome utente quando ricevi un messaggio
    if msg.from
      Whitelist.salva_nome_utente(msg.from.id, msg.from.first_name, msg.from.last_name)
    end

    # 🔥 PRIMA gestisci le foto in chat privata
    if msg.photo && msg.photo.any? && msg.chat.type == "private"
      handle_private_photo(bot, msg, chat_id, user_id)
      return
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

    # Cerca la pending action specifica per questo utente
    pending = DB.get_first_row(
      "SELECT * FROM pending_actions WHERE chat_id = ? AND initiator_id = ? AND action LIKE 'upload_foto%'",
      [chat_id, user_id]
    )

    if pending
      puts "📸 Trovata pending action: #{pending["action"]}"

      # Estrai i parametri dalla pending action
      if pending["action"] =~ /upload_foto:(.+):(\d+):(\d+)/
        item_id = $3.to_i
        gruppo_id = pending["gruppo_id"]
        photo = msg.photo.last

        puts "📸 Associando foto all'item #{item_id} nel gruppo #{gruppo_id}"

        # CORREZIONE: Prima rimuovi TUTTE le foto esistenti per questo item, poi inserisci la nuova
        DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id])
        DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
                   [item_id, photo.file_id, photo.file_unique_id])

        # Cancella la pending action di questo utente
        DB.execute("DELETE FROM pending_actions WHERE chat_id = ? AND initiator_id = ?", [chat_id, user_id])

        # Determina se era una sostituzione o un'aggiunta
        had_previous_image = Lista.ha_immagine?(item_id)
        action_text = had_previous_image ? "sostituita" : "aggiunta"

        # Invia conferma
        bot.api.send_message(
          chat_id: chat_id,
          text: "✅ Foto #{action_text} all'articolo!",
        )

        # Aggiorna la lista
        KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id)
      else
        puts "❌ Formato pending action non riconosciuto: #{pending["action"]}"
        bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'associazione della foto.")
      end
    else
      puts "📸 Foto ricevuta ma nessuna azione pending trovata per l'utente #{user_id}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "📸 Per associare una foto a un articolo, prima clicca sull'icona 📸 accanto all'articolo nella lista.",
      )
    end
  end

  # ========================================
  # 🔑 MESSAGGI PRIVATI
  # ========================================
  def self.handle_private_message(bot, msg, chat_id, user_id)
    pending = DB.get_first_row("SELECT * FROM pending_actions WHERE chat_id = ? AND action LIKE 'naming_card%'", [chat_id])

    if pending && msg.text && !msg.text.start_with?("/")
      handle_card_naming(bot, msg, chat_id, user_id, pending)
      return
    end

    if msg.photo && msg.caption
      # Se c'è una foto con caption, usa il caption come nome della carta
      handle_photo_with_caption(bot, msg, chat_id, user_id)
      return
    elsif msg.photo && !msg.caption
      # Se c'è una foto senza caption, procedi con il flusso normale di naming
      handle_photo_without_caption(bot, msg, chat_id, user_id)
      return
    end

    case msg.text
    when "/start"
      handle_start(bot, chat_id)
    when "/newgroup"
      handle_newgroup(bot, msg, chat_id, user_id)
    when "/whois_creator"
      handle_whois_creator(bot, chat_id, user_id)
    when "/delcarta"
      CarteFedelta.show_delete_interface(bot, user_id)
    when "/reportcarte"
      CarteFedeltaGruppo.show_user_shared_cards_report(bot, user_id)
    when "/myitems", "/miei"
      handle_myitems(bot, chat_id, user_id)
    when "/whitelist_show"
      if Whitelist.is_creator?(user_id)
        handle_whitelist_show(bot, chat_id, user_id)
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
      end
    when "/pending_requests"
      if Whitelist.is_creator?(user_id)
        handle_pending_requests(bot, chat_id, user_id)
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
      end
    when /^\/whitelist_add\s+(\S+)/
      if Whitelist.is_creator?(user_id)
        user_input = $1.strip

        if user_input =~ /^\d+$/
          user_id_to_add = user_input.to_i
          Whitelist.add_user(user_id_to_add, "Utente", "Aggiunto manualmente")
          bot.api.send_message(chat_id: chat_id, text: "✅ Utente ID #{user_id_to_add} aggiunto alla whitelist!")
        else
          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Usa solo ID numerici.\n\nPer trovare l'ID di un utente, digli di usare @userinfobot",
          )
        end
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
      end
    when /^\/whitelist_remove\s+(\S+)/
      if Whitelist.is_creator?(user_id)
        user_input = $1.strip

        if user_input =~ /^\d+$/
          user_id_to_remove = user_input.to_i
          DB.execute("DELETE FROM whitelist WHERE user_id = ?", [user_id_to_remove])
          bot.api.send_message(chat_id: chat_id, text: "✅ Utente ID #{user_id_to_remove} rimosso dalla whitelist!")
        else
          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Usa solo ID numerici.\n\nPer trovare l'ID di un utente, digli di usare @userinfobot",
          )
        end
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
      end
    when "/cleanup"
      if Whitelist.is_creator?(user_id)
        CleanupManager.esegui_cleanup(bot, chat_id, user_id)
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può usare questo comando.")
      end
    when "/carte"
      CarteFedelta.show_user_cards(bot, user_id)
    when /^\/addcarta (.+)/
      CarteFedelta.add_card(bot, user_id, $1)
      # 👇 MODIFICA QUESTA PARTE PER GESTIRE L'INTERFACCIA DI AGGIUNTA AL GRUPPO
    when "/addcartagruppo"
      # Se viene usato direttamente in privato, mostra un messaggio più informativo
      bot.api.send_message(
        chat_id: chat_id,
        text: "🏢 *Aggiungi carte al gruppo*\n\n" +
              "Per aggiungere le tue carte personali a un gruppo:\n" +
              "1. Vai nel gruppo dove vuoi condividere le carte\n" +
              "2. Usa il comando `/addcartagruppo`\n" +
              "3. Riceverai questo messaggio in privato per selezionare le carte\n\n" +
              "✅ Le carte che condividi saranno visibili a tutti i membri del gruppo",
        parse_mode: "Markdown",
      )
    when "/cartegruppo", "/delcartagruppo"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Questo comando funziona solo nei gruppi. Vai nel gruppo dove vuoi gestire le carte condivise.",
      )
    when "/lista", "/checklist", "/ss"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Questo comando funziona solo nei gruppi con una lista attiva.",
      )
    end
  end

  # 🔥 AGGIUNGI QUESTI METODI NELLO STESSO FILE

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

  # 🔥 MODIFICA: Aggiorna il metodo handle_card_naming per gestire entrambi i casi

  # 🔥 MODIFICA: Gestione foto senza caption (flusso esistente)
  def self.handle_photo_without_caption(bot, msg, chat_id, user_id)
    photo = msg.photo.last  # La foto più grande

    begin
      # Salva l'azione pending
      DB.execute(
        "INSERT INTO pending_actions (chat_id, action, item_id, creato_il) VALUES (?, ?, ?, datetime('now'))",
        [chat_id, "naming_card", photo.file_id]
      )

      bot.api.send_message(
        chat_id: chat_id,
        text: "📸 Foto ricevuta! Ora inviami il *nome* della carta...",
        parse_mode: "Markdown",
      )
    rescue => e
      puts "❌ Errore gestione foto senza caption: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'elaborazione della foto.")
    end
  end

  # ========================================
  # 🏷️ NAMING CARTA DOPO SCANSIONE
  # ========================================
  def self.handle_card_naming(bot, msg, chat_id, user_id, pending)
    puts "🔍 DEBUG handle_card_naming:"
    puts "  - pending action: #{pending["action"]}"
    puts "  - messaggio testo: #{msg.text}"

    action_parts = pending["action"].split(":")

    if action_parts[0] == "naming_card_with_caption"
      # Caso: nome già fornito nel caption
      nome_carta = action_parts[1]  # Il nome dal caption
      codice_carta = msg.text.strip

      puts "🔍 Flusso CAPTION - Nome: #{nome_carta}, Codice: #{codice_carta}"

      # Procedi con la creazione della carta
      create_card_from_photo(bot, chat_id, user_id, pending["item_id"], nome_carta, codice_carta)
    elsif action_parts[0] == "naming_card"
      # Caso: nome da richiedere dopo scansione barcode (flusso originale)
      nome_carta = msg.text.strip

      puts "🔍 Flusso SCANSIONE - Nome: #{nome_carta}, Codice: #{action_parts[1]}"

      # Crea direttamente la carta con nome fornito e codice dal barcode
      create_card_from_photo(bot, chat_id, user_id, nil, nome_carta, action_parts[1])
    else
      # Caso: nome da richiedere (flusso originale senza barcode)
      nome_carta = msg.text.strip

      puts "🔍 Flusso MANUALE - Nome: #{nome_carta}"

      # Aggiorna l'azione pending per aspettare il codice
      DB.execute(
        "UPDATE pending_actions SET action = ? WHERE chat_id = ? AND action LIKE 'naming_card%'",
        ["waiting_card_code:#{nome_carta}", chat_id]
      )

      bot.api.send_message(
        chat_id: chat_id,
        text: "✅ Nome: *#{nome_carta}*\n\nOra inviami il *codice* della carta...",
        parse_mode: "Markdown",
      )
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
  # ========================================
  # 📸 FOTO PRIVATE (scansione barcode)
  # ========================================
  def self.handle_private_photo(bot, msg, chat_id, user_id)
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

  def self.handle_myitems(bot, chat_id, user_id, message_id = nil, page = 0)
    groups = DB.execute("
    SELECT DISTINCT g.id, g.nome 
    FROM gruppi g
    JOIN items i ON g.id = i.gruppo_id
    WHERE i.creato_da = ?
    ORDER BY g.nome
  ", [user_id])

    if groups.empty?
      if message_id
        bot.api.edit_message_text(
          chat_id: chat_id,
          message_id: message_id,
          text: "📭 Non hai articoli in nessun gruppo.",
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "📭 Non hai articoli in nessun gruppo.")
      end
      return
    end

    # Paginazione per gruppi
    total_pages = (groups.size.to_f / GROUPS_PER_PAGE).ceil
    page = [page, total_pages - 1].min
    page = [page, 0].max

    start_index = page * GROUPS_PER_PAGE
    end_index = [start_index + GROUPS_PER_PAGE - 1, groups.size - 1].min
    groups_pagina = groups[start_index..end_index] || []

    # Costruisci il testo usando il metodo helper per ogni gruppo
    text = "<b>📋 I TUOI ARTICOLI - Pagina #{page + 1}/#{total_pages}</b>\n\n"

    groups_pagina.each do |group|
      group_id = group["id"]
      group_name = group["nome"]

      # Prendi solo gli articoli di questo utente in questo gruppo
      user_items = DB.execute("
      SELECT i.*, u.initials as user_initials
      FROM items i
      LEFT JOIN user_names u ON i.creato_da = u.user_id
      WHERE i.gruppo_id = ? AND i.creato_da = ?
      ORDER BY i.comprato, i.nome
    ", [group_id, user_id])

      # Aggiungi l'header del gruppo
      text += "🏠 <b>#{group_name}</b> (#{user_items.size} articoli)\n"

      # Usa il metodo helper per formattare gli articoli di questo gruppo con TUTTE le icone
      articles_text = KeyboardGenerator.formatta_articoli_per_myitems(user_items)
      text += articles_text

      text += "\n" + "─" * 30 + "\n\n"
    end

    # Bottoni di navigazione
    nav_buttons = []
    if total_pages > 1
      row = []

      if page > 0
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️ Pagina #{page}",
          callback_data: "myitems_page:#{user_id}:#{page - 1}",
        )
      end

      row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{page + 1}/#{total_pages}",
        callback_data: "noop",
      )

      if page < total_pages - 1
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "Pagina #{page + 2} ▶️",
          callback_data: "myitems_page:#{user_id}:#{page + 1}",
        )
      end

      nav_buttons = [row] if row.any?
    end

    # Bottoni di controllo
    control_buttons = [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🔄 Aggiorna",
          callback_data: "myitems_refresh:#{user_id}:#{page}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "❌ Chiudi",
          callback_data: "checklist_close:#{chat_id}",
        ),
      ],
    ]

    inline_keyboard = nav_buttons + control_buttons
    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    if message_id
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: message_id,
        text: text,
        reply_markup: markup,
        parse_mode: "HTML",
      )
    else
      bot.api.send_message(
        chat_id: chat_id,
        text: text,
        reply_markup: markup,
        parse_mode: "HTML",
      )
    end
  end

  def self.handle_start(bot, chat_id)
    bot.api.send_message(chat_id: chat_id, text: "👋 Benvenuto! Usa /newgroup per creare un gruppo virtuale.")
  end

  def self.handle_whitelist_show(bot, chat_id, user_id)
    creator_id = Whitelist.get_creator_id
    if creator_id.to_i != user_id.to_i
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
      return
    end

    users = Whitelist.all_users
    if users.empty?
      bot.api.send_message(chat_id: chat_id, text: "ℹ️ Nessun utente in whitelist.")
      return
    end

    elenco = users.map do |user|
      "👤 #{user["first_name"]} #{user["last_name"]} (@#{user["username"]}) - ID: #{user["user_id"]}"
    end.join("\n")

    bot.api.send_message(chat_id: chat_id, text: "📋 Whitelist:\n#{elenco}")
  end

  def self.handle_pending_requests(bot, chat_id, user_id)
    creator_id = Whitelist.get_creator_id
    if creator_id.to_i != user_id.to_i
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
      return
    end

    pending = Whitelist.get_pending_requests
    if pending.empty?
      bot.api.send_message(chat_id: chat_id, text: "ℹ️ Nessuna richiesta in attesa.")
      return
    end

    pending.each do |user|
      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "✅ Approva",
              callback_data: "approve_user:#{user["user_id"]}:#{user["username"]}:#{user["first_name"]}_#{user["last_name"]}",
            ),
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Rifiuta",
              callback_data: "reject_user:#{user["user_id"]}",
            ),
          ],
        ],
      )

      bot.api.send_message(
        chat_id: chat_id,
        text: "🔔 *Richiesta di accesso*\n\n" \
              "👤 #{user["first_name"]} #{user["last_name"]}\n" \
              "📧 @#{user["username"]}\n" \
              "🆔 #{user["user_id"]}",
        parse_mode: "Markdown",
        reply_markup: keyboard,
      )
    end
  end
  def self.handle_whitelist_remove(bot, chat_id, user_id)
    creator_id = Whitelist.get_creator_id
    if creator_id.to_i != user_id.to_i
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
      return
    end

    DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action) VALUES (?, ?)",
               [chat_id, "whitelist_remove"])

    bot.api.send_message(
      chat_id: chat_id,
      text: "✍️ Invia l'ID utente OPPURE @username da rimuovere dalla whitelist:",
    )
  end

  def self.handle_whitelist_add(bot, chat_id, user_id)
    creator_id = Whitelist.get_creator_id
    if creator_id.to_i != user_id.to_i
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Solo il creatore può usare questo comando.")
      return
    end

    DB.execute("INSERT OR REPLACE INTO pending_actions (chat_id, action) VALUES (?, ?)",
               [chat_id, "whitelist_add"])

    bot.api.send_message(
      chat_id: chat_id,
      text: "✍️ Invia l'ID utente OPPURE @username da aggiungere alla whitelist:\n\nEsempi:\n• 123456789\n• @pippo \n• @username",
    )
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

    # Avvisa l’utente
    bot.api.send_message(
      chat_id: chat_id,
      text: "📨 La tua richiesta di accesso è stata inviata all'amministratore.\nRiceverai una notifica quando verrà approvata.",
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
      "🆔 #{row["id"]} | #{row["nome"]} | 👤 #{row["creato_da"]} | 💬 #{row["chat_id"]}"
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
      items_count = DB.execute("DELETE FROM items WHERE gruppo_id = ?", [gruppo["id"]])

      # 2. POI cancella il gruppo
      DB.execute("DELETE FROM gruppi WHERE id = ?", [gruppo["id"]])

      puts "🔍 [DEL] Cancellati #{items_count} items del gruppo #{gruppo["id"]}"
      puts "🔍 [DEL] Gruppo #{gruppo["id"]} cancellato"

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

    if gruppo_in_attesa && !msg.text&.start_with?("/delgroup")
      # 🔄 TROVATO GRUPPO IN ATTESA - Esegui accoppiamento
      DB.execute("UPDATE gruppi SET chat_id = ?, nome = ? WHERE id = ?",
                 [chat_id, msg.chat.title, gruppo_in_attesa["id"]])

      bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo accoppiato! Benvenuto nel tuo nuovo gruppo della spesa.")
      puts "🎯 Gruppo accoppiato: #{gruppo_in_attesa["id"]} → chat_id #{chat_id}"

      # Ricarica il gruppo aggiornato
      gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [gruppo_in_attesa["id"]])
    else
      # Comportamento normale: cerca gruppo esistente
      gruppo = GroupManager.get_gruppo_by_chat_id(chat_id)
    end

    # Aggiorna il nome reale da Telegram se serve
    ensure_group_name(bot, msg, gruppo)

    if gruppo.nil?
      case msg.text
      when "/lista", "/lista@#{bot_username}", "/checklist"
        bot.api.send_message(chat_id: chat_id, text: "📭 Nessuna lista della spesa attiva.\nUsa /newgroup in chat privata per crearne una.")
        return
      when "/ss", "/ss@#{bot_username}"
        bot.api.send_message(chat_id: chat_id, text: "📷 Nessuna lista da visualizzare.")
        return
      when "/delgroup", "/delgroup@#{bot_username}"
        bot.api.send_message(chat_id: chat_id, text: "❌ Nessun gruppo da cancellare.")
        return
      when "/newgroup", "/newgroup@#{bot_username}"
        # Cerca gruppo in attesa per questo utente
        gruppo_in_attesa = GroupManager.find_pending_by_user(user_id)

        if gruppo_in_attesa
          # Accoppiamento
          GroupManager.update_chat_id(gruppo_in_attesa["id"], chat_id, msg.chat.title)
          bot.api.send_message(chat_id: chat_id, text: "✅ Gruppo accoppiato! Ora puoi usare +articolo per aggiungere elementi.")
        else
          bot.api.send_message(chat_id: chat_id,
                               text: "❌ Nessun gruppo in attesa. Usa /newgroup in chat privata prima.")
        end
        return
      else
        # Per +articolo e altri messaggi - messaggio generico
        if msg.text&.start_with?("+")
          bot.api.send_message(chat_id: chat_id, text: "📭 Crea prima una lista con /newgroup in chat privata")
        end
        return
      end
    end

    case msg.text
    when "/start", "/start@#{bot_username}"
      return
    when "/ss", "/ss@#{bot_username}"
      handle_screenshot_command(bot, msg, gruppo)
      return
    when "/checklist", "/checklist@#{bot_username}"
      topic_id = msg.message_thread_id || 0
      puts "[CHECKLIST] Richiesta per gruppo #{gruppo} topic #{topic_id}"
      StoricoManager.genera_checklist(bot, msg, gruppo["id"], topic_id)

      return
    when "/carte", "/carte@#{bot_username}"
      CarteFedelta.show_user_cards(bot, user_id)
      return
    when "/cartegruppo", "/cartegruppo@#{bot_username}"
      CarteFedeltaGruppo.show_group_cards(bot, gruppo["id"], chat_id, user_id)  # 👈 chat_id invece di user_id
      return
    when "/delcartagruppo", "/delcartagruppo@#{bot_username}"
      CarteFedeltaGruppo.handle_delcartagruppo(bot, msg, chat_id, user_id, gruppo)
      return
    when "/delgroup", "/delgroup@#{bot_username}"
      handle_delgroup(bot, msg, chat_id, user_id)
      return
    when "/lista", "/lista@#{bot_username}"
      KeyboardGenerator.genera_lista(bot, chat_id, gruppo["id"], user_id)
      return
    when "?"
      topic_id = msg.message_thread_id || 0
      handle_question_command(bot, chat_id, user_id, gruppo, topic_id)
      return
    when "!"
      KeyboardGenerator.genera_lista_testo(bot, chat_id, gruppo["id"], user_id, message_id = nil)
      return
    when "/delcarta", "/delcarta@#{bot_username}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Usa /delcarta in chat privata per eliminare carte personali.",
      )
      return
    when "/reportcarte", "/reportcarte@#{bot_username}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Usa /reportcarte in chat privata per vedere il report delle carte condivise.",
      )
      return
    when "/listagruppi", "/listagruppi@#{bot_username}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Usa /listagruppi in chat privata per vedere l-elenco dei gruppi.",
      )
      return
    end

    # 🔥 MODIFICA PRINCIPALE: Gestione di /addcartagruppo
    if msg.text&.start_with?("/addcartagruppo")
      if gruppo
        # Invia l'interfaccia nella chat privata dell'utente
        CarteFedeltaGruppo.handle_addcartagruppo(bot, msg, chat_id, user_id, gruppo)

        # Conferma nel gruppo che stai inviando l'interfaccia in privato
        bot.api.send_message(
          chat_id: chat_id,
          text: "🏢 Ti ho inviato un messaggio in privato per gestire le carte del gruppo.",
          reply_to_message_id: msg.message_id,
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Nessun gruppo attivo. Usa /newgroup in chat privata.")
      end
    elsif msg.text&.start_with?("+")
    puts "chiamo handle_plus_command"
      handle_plus_command(bot, msg, chat_id, user_id, gruppo)
    elsif msg.text&.start_with?("/delcartagruppo")
      CarteFedeltaGruppo.handle_delcartagruppo(bot, msg, chat_id, user_id, gruppo)
    else
      handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
    end
  end
  def self.handle_addcartagruppo(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo

    # Verifica che l'utente sia whitelistato
    unless Whitelist.is_allowed?(user_id)
      bot.api.send_message(chat_id: chat_id, text: "❌ Solo utenti autorizzati possono aggiungere carte al gruppo.")
      return
    end

    # 🔥 CORREZIONE: usa regex per rimuovere il comando con o senza username
    args = msg.text.sub(/\/addcartagruppo(@\w+)?/, "").strip

    if args.empty?
      # 🔥 NUOVO: Mostra interfaccia con le carte personali
      CarteFedeltaGruppo.show_add_to_group_interface(bot, chat_id, gruppo["id"], user_id)
    else
      # Comportamento esistente: aggiungi carta manualmente
      CarteFedeltaGruppo.add_group_card(bot, chat_id, gruppo["id"], user_id, args)
    end
  end

  def self.handle_question_command(bot, chat_id, user_id, gruppo, topic_id)
    # MODIFICA: Passa topic_id al generatore normale
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo["id"], user_id, nil, 0, topic_id)
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
            StoricoManager.aggiorna_da_aggiunta(articolo.strip, gruppo["id"],topic_id)
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
  # ========================================
  # PENDING ACTIONS
  # ========================================

  def self.handle_pending_actions(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo

    pending = DB.get_first_row(
      "SELECT * FROM pending_actions WHERE chat_id = ?",
      [chat_id]
    )
    return unless pending &&
                  pending["action"].to_s.start_with?("add") &&
                  pending["gruppo_id"] == gruppo["id"]

    # 🔥 TOPIC SEMPRE DAL MESSAGGIO
    topic_id = msg.message_thread_id || 0

    # ⏱ Timeout (120 secondi)
    timeout_seconds = 120
    created_time = DateTime
      .strptime(pending["creato_il"], "%Y-%m-%d %H:%M:%S")
      .to_time
    expired = (Time.now - created_time) > timeout_seconds

    if expired
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "⏰ Tempo scaduto, aggiunta annullata.",
      )
      return
    end

    # ❌ Solo chi ha iniziato il pending può completarlo
    initiator_id = pending["initiator_id"].to_i
    if initiator_id != user_id
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "⚠️ Solo chi ha avviato l'aggiunta può completarla o annullarla.",
      )
      return
    end

    # ❌ Annulla manualmente
    if msg.text == "/annulla"
      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "❌ Aggiunta annullata.",
      )
      return
    end

    # ➕ Aggiunta vera e propria
    if msg.text && !msg.text.start_with?("/")
      added_items = msg.text.split(",").map(&:strip)

      added_items.each do |articolo|
        next if articolo.empty?

        Lista.aggiungi(
          pending["gruppo_id"],
          user_id,
          articolo,
          topic_id
        )
        StoricoManager.aggiorna_da_aggiunta(
          articolo,
          gruppo["id"]
        )
      end

      DB.execute("DELETE FROM pending_actions WHERE chat_id = ?", [chat_id])

      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "✅ #{msg.from.first_name} ha aggiunto: #{added_items.join(", ")}",
      )

      KeyboardGenerator.genera_lista(
        bot,
        chat_id,
        pending["gruppo_id"],
        user_id,
        nil,
        0,
        topic_id
      )
    end
  end

  # Helper: trova un TTF disponibile su Android/Termux
  def self.find_ttf_font_path
    candidates = [
      "/system/fonts/DroidSans.ttf",
      "/system/fonts/DroidSans-Regular.ttf",
      "/system/fonts/Roboto-Regular.ttf",
      "/system/fonts/NotoSans-Regular.ttf",
      "/system/fonts/DejaVuSans.ttf",
      "/system/fonts/Arial.ttf",
    ]
    candidates.find { |p| File.exist?(p) }
  end

  def self.sanitize_pdf_text(str)
    return "" if str.nil?
    s = str.to_s.dup
    # rimuovi i controlli ASCII
    s.gsub!(/[\u0000-\u001F]/, "")
    # sostituisci sequenze invalide/undef con vuoto
    s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    # rimuovi larghe famiglie emoji (opzionale)
    s.gsub(/[\u{1F300}-\u{1F6FF}\u{1F900}-\u{1F9FF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/, "")
  end

  def self.handle_screenshot_command(bot, msg, gruppo)
    topic_id = msg.message_thread_id || 0

    begin
      items = Lista.tutti(gruppo["id"], topic_id)
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
              bold_italic: font_path,
            },
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
            res = chat_info["result"] || chat_info
            if res && res["photo"]
              photo = res["photo"]
              photo_file_id = photo["big_file_id"] || photo["small_file_id"] || photo["big_file_unique_id"]
            end
          elsif chat_info.respond_to?(:photo) && chat_info.photo
            # oggetto tipizzato (Telegram::Bot::Types::Chat / ChatFullInfo)
            photo = chat_info.photo
            photo_file_id = photo.respond_to?(:big_file_id) ? photo.big_file_id : nil
          end

          if photo_file_id
            file_info = bot.api.get_file(file_id: photo_file_id) rescue nil
            file_path = nil
            if file_info.is_a?(Hash) && file_info["result"]
              file_path = file_info["result"]["file_path"]
            elsif file_info.respond_to?(:file_path)
              file_path = file_info.file_path rescue nil
            end

            if file_path
              token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")
              if token && token.to_s.strip != ""
                file_url = "https://api.telegram.org/file/bot#{token}/#{file_path}"
                Tempfile.create(["group_logo", ".jpg"]) do |tmp|
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
        header_text = sanitize_pdf_text("LISTA DELLA SPESA - #{gruppo["nome"]}")
        pdf.move_down 6
        pdf.text header_text, size: 18, style: :bold, align: :center
        pdf.move_down 8
        pdf.stroke_horizontal_rule
        pdf.move_down 12

        # Tabella items
        table_data = [["Stato", "Articolo", "Aggiunto da"]]
        items.each do |it|
          #status = it['comprato'] == 1 ? "[X]" : "[ ]"
          status = it["comprato"] && !it["comprato"].empty? ? " [X](#{it["comprato"]})" : "[ ]"
          nome = sanitize_pdf_text(it["nome"])
          initials = sanitize_pdf_text(it["user_initials"] || "")
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
        pdf.text "Aggiornato: #{Time.now.strftime("%d/%m/%Y %H:%M")}", size: 9, align: :center
      end

      # invio file
      bot.api.send_document(
        chat_id: msg.chat.id,
        document: Faraday::UploadIO.new(filename, "application/pdf"),
        caption: "📋 Lista in PDF - Condividi su WhatsApp, email o stampa!",
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
      items ||= Lista.tutti(gruppo["id"])
      if items.nil? || items.empty?
        bot.api.send_message(chat_id: chat_id, text: "📝 La lista è vuota!")
        return
      end

      comprati = items.count { |i| i["comprato"] == 1 }
      totali = items.size

      text_response = "*LISTA DELLA SPESA* — #{sanitize_pdf_text(gruppo["nome"])}\n"
      text_response += "_Completati: #{comprati}/#{totali}_\n\n"
      items.each do |it|
        stato = it["comprato"] == 1 ? "[X]" : "[ ]"
        line = "#{stato} #{sanitize_pdf_text(it["nome"])}"
        line += " — #{sanitize_pdf_text(it["user_initials"] || "")}" unless (it["user_initials"].nil? || it["user_initials"].strip.empty?)
        text_response += "#{line}\n"
      end
      text_response += "\n_Invio in formato testo a causa di un errore nella generazione PDF_"

      bot.api.send_message(chat_id: chat_id, text: text_response, parse_mode: "Markdown")
    rescue => e
      puts "❌ Errore anche nel fallback testo: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nel generare la lista. Riprova più tardi.")
    end
  end

  def self.list_available_fonts
    font_dirs = [
      "/system/fonts",
      "/data/data/com.termux/files/usr/share/fonts",
      "/usr/share/fonts",
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
      items = Lista.tutti(gruppo["id"])

      if items.empty?
        bot.api.send_message(
          chat_id: msg.chat.id,
          text: "📝 La lista è vuota! Non c'è nulla da condividere.",
        )
        return
      end

      # Crea file di testo semplice
      file_content = "🛒 LISTA DELLA SPESA 🛒\n\n"

      items.each do |item|
        status = item["comprato"] == 1 ? "[✓]" : "[ ]"
        user_badge = item["user_initials"] ? "#{item["user_initials"]}-" : ""
        file_content += "#{status} #{user_badge}#{item["nome"]}\n"
      end

      file_content += "\nAggiornato: #{Time.now.strftime("%d/%m/%Y %H:%M")}"
      file_content += "\nGenerato da @hassMB_bot"

      # Salva come file .txt
      filename = "/data/data/com.termux/files/home/spesa/lista_#{Time.now.to_i}.txt"
      File.write(filename, file_content)

      # Invia come file
      bot.api.send_document(
        chat_id: msg.chat.id,
        document: Faraday::UploadIO.new(filename, "text/plain"),
        caption: "📋 Clicca sul file e scegli 'Condividi' per inviare via WhatsApp, Email, ecc.",
      )

      # Pulisci
      File.delete(filename) if File.exist?(filename)
    rescue => e
      puts "❌ Errore generazione screenshot: #{e.message}"
      # Fallback a messaggio semplice
      bot.api.send_message(
        chat_id: msg.chat.id,
        text: "❌ Impossibile generare il file. Usa /lista per vedere la lista.",
      )
    end
  end
end
