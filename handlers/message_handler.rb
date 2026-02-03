# handlers/message_handler.rb
# In alto al file aggiungi:
require_relative "../utils/keyboard_generator"
require_relative "../models/context"
require_relative "../models/carte_fedelta"
require_relative "../models/carte_fedelta_gruppo"
require_relative "./storico_manager"

require_relative "../db"

class MessageHandler
  # ==============================================================================
  # ROUTER PRINCIPALE (DISPATCHER)
  def self.route(bot, msg, context)
    u_id = msg.from.id
    g_chat_id = msg.chat.id
    # 1. LOGICA PER GRUPPI (REALE)
    unless context.private_chat?
      # LOG DI EMERGENZA: Vediamo l'intero oggetto messaggio quando accade qualcosa
      if msg.forum_topic_created || msg.forum_topic_edited
        puts "[RAW_SERVICE_MSG] Ricevuto messaggio di servizio: #{msg.to_json}"
      end
      # Sincronizza il nome del topic se Telegram ci invia un evento di creazione/modifica
      TopicManager.sincronizza(msg)

      gruppo = DataManager.prendi_gruppo_da_chat_id(g_chat_id)
      context.config["db_id"] = gruppo ? gruppo["id"].to_i : 0

      # Gestione Topic
      t_id_msg = msg.respond_to?(:message_thread_id) ? msg.message_thread_id : nil
      context.config["topic_id"] = t_id_msg ? t_id_msg.to_i : 0

      puts "[ROUTING] 🏢 Gruppo: G:#{context.config["db_id"]} T:#{context.config["topic_id"]}"

      # 2. LOGICA PER PRIVATA (TELECOMANDO)
    else
      puts "[ROUTING] 🏠 Chat Privata: Carico target dal DB..."
      config_salvata = DataManager.carica_config_utente(u_id) || {}

      # ALLINEAMENTO CHIAVI: Usa le stesse chiavi ovunque
      g_id = config_salvata["db_id"] || config_salvata["target_g"]
      t_id = config_salvata["topic_id"] || config_salvata["target_t"]

      if g_id && g_id.to_i != 0
        context.config["db_id"] = g_id.to_i
        context.config["topic_id"] = (t_id || 0).to_i
        puts "[ROUTING] 🎯 Target recuperato: G:#{context.config["db_id"]} T:#{context.config["topic_id"]}"
      else
        context.config["db_id"] = 0
        context.config["topic_id"] = 0
        puts "[ROUTING] 👤 Default: Lista Personale"
      end
    end

    # 3. GESTIONE FOTO (Blindata contro i nil)
    if msg.photo && !msg.photo.empty?
      return self.handle_photo_bridge(bot, msg, context)
    end

    DataManager.salva_config_utente(u_id, context.config)
    text = msg.text.to_s.strip
    return if text.empty? # Esci se non c'è testo (evita crash su messaggi di sistema)
    cmd = text.split("@").first.strip.downcase rescue ""
    puts "[ROUTING] 🚦 Smistamento: '#{text[0..20]}...' (Scope: #{context.scope})"

    case text # Usiamo text per matchare anche le etichette dei bottoni
    when /^\/(start|help)/
      self.core_start(bot, context)
      # Se siamo in privata, forziamo la comparsa del menu
      if context.private_chat?
        KeyboardGenerator.show_private_keyboard(bot, context.chat_id, context)
      end

      # In handlers/message_handler.rb

    when "/setup_pin"
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i

      kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🛒 MOSTRA LISTA AGGIORNATA",
        callback_data: "trigger_list:#{g_id}:#{t_id}",
      )]]

      markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)

      # 'sent' è l'oggetto Message (guarda il tuo log, c'è già tutto dentro)
      sent = bot.api.send_message(
        chat_id: msg.chat.id,
        message_thread_id: (t_id > 0 ? t_id : nil),
        text: "📌 <b>Pannello Spesa - Topic #{t_id}</b>\nUsa questo tasto per richiamare la lista in questo thread.",
        reply_markup: markup,
        parse_mode: "HTML",
      )

      begin
        # ACCESSO DIRETTO: sent.message_id, senza .result!
        bot.api.pin_chat_message(
          chat_id: msg.chat.id,
          message_id: sent.message_id,
        )
        puts "[DEBUG] ✅ Pannello pinnato: ID #{sent.message_id} nel Topic #{t_id}"
      rescue => e
        puts "[ERROR] Impossibile pinnare: #{e.message}"
      end
    when /^\/checklist/
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i

      kb = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)

      if kb
        bot.api.send_message(
          chat_id: context.chat_id,
          message_thread_id: context.topic_id, # <--- AGGIUNGI QUESTO
          text: "📋 *Checklist Intelligente*\nSeleziona gli articoli:",
          reply_markup: kb,
          parse_mode: "Markdown",
        )
      else
        bot.api.send_message(
          chat_id: context.chat_id,
          message_thread_id: context.topic_id, # <--- AGGIUNGI QUESTO
          text: "Storico vuoto per questo contesto.",
        )
      end
      return
    when "/addcartagruppo"
      if g_chat_id < 0
        gruppo = DataManager.prendi_gruppo_da_chat_id(g_chat_id)
        if gruppo
          CarteFedeltaGruppo.show_add_to_group_interface(bot, u_id, gruppo["id"], nil)
          bot.api.send_message(chat_id: g_chat_id, message_thread_id: msg.message_thread_id, text: "✉️ @#{msg.from.username}, ti ho inviato la gestione delle carte in privato.")
        end
      end
    when "/carte", "/cartegruppo"
      CarteFedeltaGruppo.show_group_cards(bot, context.config["db_id"], g_chat_id, u_id, context.config["topic_id"])
    when "/miecartecondivise"
      CarteFedeltaGruppo.show_user_shared_cards_report(bot, u_id)
    when "💳 LE MIE CARTE"
      # Chiama la nuova griglia aggregata (Personali + Gruppi)
      # Usiamo il metodo della classe base CarteFedelta
      CarteFedelta.mostra_personali(bot, u_id)
    when "/addcarta"
      bot.api.send_message(chat_id: u_id, text: "✍️ Invia la foto della carta con il nome nella didascalia (caption).")
    when "/delcarta"
      CarteFedelta.show_delete_interface(bot, u_id)
    when /^\?(.*)/
      # 1. Recupero ID Gruppo dal DB (config) e Topic dal messaggio
      g_id = context.config["db_id"].to_i
      t_id = (msg.message_thread_id || 0).to_i

      # 2. Recupero Dati
      items = DataManager.prendi_per_contesto(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)

      # 3. CHIAMATA CORRETTA: devi passare TUTTI i parametri nell'ordine giusto
      # bot, context, items, header, g_id, t_id, page
      self.core_mostra_lista(bot, context, items, header, g_id, t_id, 0)
    when "/tutti", "📦 TUTTI GLI ARTICOLI"
      # Passiamo chat_id e user_id estratti dal context, non l'intero oggetto
      self.handle_myitems(bot, context.chat_id, context.user_id, msg, 0, true)
    when "/miei", "📋 I MIEI ARTICOLI"
      self.handle_myitems(bot, context.chat_id, context.user_id, msg, 0, false)
    when /^🛒 LISTA/ # <--- Il simbolo ^ indica "inizia con". Corrisponde a ogni variazione del tasto.
      conf = DataManager.carica_config_utente(u_id) || {}

      # Usa la logica a doppia chiave per compatibilità
      g_id = (conf["db_id"] || conf["target_g"] || 0).to_i
      t_id = (conf["topic_id"] || conf["target_t"] || 0).to_i

      context.config["db_id"] = g_id
      context.config["topic_id"] = t_id

      items = DataManager.prendi_per_contesto(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)

      self.core_mostra_lista(bot, context, items, header, g_id, t_id)
    when "/private", "⚙️ IMPOSTA GRUPPO"
      puts "[ROUTING] ✅ Attivazione Menu Privato e Selettore"
      # 1. Mostra la tastiera fisica (🛒 LISTA, ecc.)
      #KeyboardGenerator.show_private_keyboard(bot, context.chat_id)

      # 2. Mostra i bottoni inline per scegliere il gruppo target
      # Ripristiniamo la chiamata che avevi in produzione:
      KeyboardGenerator.show_group_selector(bot, u_id)
    when "➕ AGGIUNGI PRODOTTO"
      # 1. Chiedi al DB, non al context!
      conf = DataManager.carica_config_utente(u_id)
      g_id = conf ? conf["target_g"].to_i : 0
      t_id = conf ? conf["target_t"].to_i : 0

      # 2. Imposta il pending sul target reale (fondamentale per core_aggiunta)
      DataManager.set_pending(chat_id: context.chat_id, topic_id: 0, action: "add:#{msg.from.first_name}", gruppo_id: g_id)

      # 3. Genera l'intestazione corretta
      destinazione = DataManager.genera_header_contesto(g_id, t_id)

      bot.api.send_message(
        chat_id: context.chat_id,
        text: "✍️ <b>#{msg.from.first_name}</b>, scrivi gli articoli per:\n#{destinazione}",
        parse_mode: "HTML",
      )
    when /^\/(start|help)/
      self.core_start(bot, context)
    when /^\+(.*)/
      # Lista di Gruppo/Contesto attivo
      self.core_aggiunta(bot, context, $1.to_s.strip, false)
    when /^\*(.*)/
      # Lista Personale (Shortcut)
      self.core_aggiunta(bot, context, $1.to_s.strip, true)
    when "/cleanup"
      self.core_cleanup(bot, context)
    else
      self.handle_pending_responses(bot, msg, context)
    end
  end
  # ==============================================================================
  # FUNZIONI CORE (I PILASTRI)
  # ==============================================================================
  # In message_handler.rb, modifica core_mostra_lista
  # message_handler.rb

  # handlers/message_handler.rb
  # In handlers/message_handler.rb
  def self.carica_contesto_privato(user_id, context)
    # Usiamo il tuo metodo esistente a riga 331 di db.rb
    config = DataManager.carica_config_utente(user_id)

    if config.is_a?(Hash) && config["target_g"]
      context.config["db_id"] = config["target_g"].to_i
      context.config["topic_id"] = (config["target_t"] || 0).to_i
    else
      # Default se non ha mai scelto nulla
      context.config["db_id"] = 0
      context.config["topic_id"] = 0
    end
  end

  def self.core_mostra_lista(bot, context, items, header, g_id, t_id, page = 0)
    # Rimuovi il caricamento dal DB qui dentro, usa quelli passati come argomenti
    ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

    target_thread = context.private_chat? ? nil : (t_id.to_i > 0 ? t_id.to_i : nil)

    begin
      puts "[CORE] 📤 INVIO - Chat: #{context.chat_id}, G:#{g_id}, T:#{t_id}"
      bot.api.send_message(
        chat_id: context.chat_id,
        message_thread_id: target_thread,
        text: ui[:text],
        reply_markup: ui[:markup],
        parse_mode: "HTML",
      )
    rescue => e
      puts "❌ [CORE ERROR] #{e.message}"
    end
  end

  def self.show_private_keyboard(bot, chat_id)
    puts "📟 [DEBUG] Visualizzazione tastiera privata per: #{chat_id}"

    markup = KeyboardGenerator.tastiera_privata_fissa

    bot.api.send_message(
      chat_id: chat_id,
      text: "🎮 *Pannello di Controllo*\nUsa i tasti in basso per gestire la spesa.",
      reply_markup: markup,
      parse_mode: "Markdown",
    )
  end

  def self.core_cambio_modalita(bot, context)
    # Nome corretto del metodo presente in db.rb a riga 231
    destinazioni = DataManager.prendi_destinazioni_censite(context.user_id)
    markup = KeyboardGenerator.tastiera_scelta_gruppo(destinazioni)

    bot.api.send_message(
      chat_id: context.chat_id,
      text: "🎯 *Seleziona Destinazione*\nDove vuoi inviare i prodotti?",
      reply_markup: markup,
      parse_mode: "Markdown",
    )
  end

  # CORE AGGIUNTA (+)
  def self.core_aggiunta(bot, context, contenuto, force_personal = false)
    u_id = context.user_id

    if force_personal
      g_id = 0
      t_id = 0
      header = "📋 I TUOI ARTICOLI"
      puts "[CORE] ⭐️ Aggiunta rapida alla Lista Personale"
    else
      g_id = context.config ? context.config["db_id"].to_i : 0
      t_id = context.config ? context.config["topic_id"].to_i : 0
      header = DataManager.genera_header_contesto(g_id, t_id)
    end

    puts "[TRACE] 🚀 START core_aggiunta - U:#{u_id} G:#{g_id} T:#{t_id}"

    # 1. SCRITTURA
    DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: u_id, items_text: contenuto, topic_id: t_id)
    puts "[TRACE] ✅ Articoli scritti nel DB"

    # 2. CARICAMENTO DATI
    items = DataManager.prendi_articoli_ordinati(g_id, t_id)

    # AGGIORNAMENTO: Genera l'header dinamico SOLO se non è forzato quello personale
    unless force_personal
      header = DataManager.genera_header_contesto(g_id, t_id)
    end

    puts "[TRACE] 📊 Dati caricati per UI. Items: #{items.size} | Header: #{header}"

    # 3. NOTIFICA GRUPPO
    # In MessageHandler.core_aggiunta

    # 3. NOTIFICA GRUPPO
    # Inviamo la notifica SOLO SE l'utente sta scrivendo in chat PRIVATA
    # e il target (g_id) è un gruppo.
    if context.scope == :private && g_id != 0
      real_chat_id = DataManager.get_real_chat_id(g_id)

      if real_chat_id
        # Recuperiamo le initials dai dati appena caricati [cite: 3, 35]
        mio_item = items.find { |i| i["creato_da"] == u_id }
        init = mio_item ? mio_item["autore_init"] : "U"[cite: 2]

        begin
          bot.api.send_message(
            chat_id: real_chat_id,
            text: "➕ <b>#{init}</b>: #{contenuto.gsub(/^[\+\*]/, "").strip}",
            parse_mode: "HTML",
            message_thread_id: (t_id > 0 ? t_id : nil),
            disable_notification: true,
          )
        rescue => e
          puts "[TRACE] ❌ Errore API Notifica: #{e.message}"
        end
      end
    end
    # 4. REFRESH LISTA
    puts "[TRACE] 🔄 Chiamata core_mostra_lista (7 params)"
    self.core_mostra_lista(bot, context, items, header, g_id, t_id, 0)
  end

  def self.refresh_lista_spesa(bot, callback, g_id, t_id, page, show_all, user_id)
    if show_all
      # Se veniamo dal menu "I Miei Articoli" (cartelle), usiamo il suo refresh dedicato [cite: 12]
      self.handle_myitems(bot, callback.message.chat.id, user_id, callback, page, true)
    else
      # Recupero dati aggiornati [cite: 10]
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)

      # Header coerente: se g_id è 0 è la lista personale dello shortcut "*"
      header = (g_id == 0) ? "📋 I TUOI ARTICOLI" : DataManager.genera_header_contesto(g_id, t_id)

      # Generazione interfaccia [cite: 10]
      ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

      begin
        bot.api.edit_message_text(
          chat_id: callback.message.chat.id,
          message_id: callback.message.message_id,
          text: ui[:text],
          reply_markup: ui[:markup],
          parse_mode: "HTML",
        )
      rescue Telegram::Bot::Exceptions::ResponseError => e
        # Ignoriamo se l'utente clicca freneticamente e il contenuto non cambia [cite: 11, 42]
        raise e unless e.message.include?("message is not modified")
        puts "[DEBUG] Refresh lista: contenuto identico"
      end
    end
  end

  # CORE STORICO (?)
  def self.core_storico(bot, context, query)
    puts "[CORE] 🔍 Esecuzione Ricerca (?)"
    g_id = context.lista_personale? ? 0 : (context.config["db_id"] || 0)
    t_id = context.lista_personale? ? 0 : (context.config["topic_id"] || 0)

    risultati = DataManager.ricerca_storico(gruppo_id: g_id, topic_id: t_id, query: query.empty? ? nil : query)

    if risultati.any?
      testo = "📜 **Storico / Suggerimenti:**\n" + risultati.map { |r| "• #{r["nome"]} (#{r["conteggio"]})" }.join("\n")
      bot.api.send_message(chat_id: context.chat_id, text: testo, parse_mode: "Markdown")
    else
      bot.api.send_message(chat_id: context.chat_id, text: "❓ Storico vuoto.")
    end
  end

  # ==============================================================================
  # METODI PONTE E FALLBACK
  # ==============================================================================
  def self.handle_pending_responses(bot, msg, context)
    pending = DataManager.ottieni_pending(context.chat_id, context.topic_id)
    if pending && pending["action"].start_with?("add")
      # Qui dentro mettiamo la chiamata UNICA
      self.core_aggiunta(bot, context, msg.text)
      DataManager.clear_pending(chat_id: context.chat_id, topic_id: context.topic_id)
    end
  end

  def self.handle_photo_bridge(bot, msg, context)
    u_id = msg.from.id
    caption = msg.caption.to_s.strip

    if context.private_chat?
      if caption.empty?
        return bot.api.send_message(chat_id: u_id, text: "📸 Per salvare una carta, invia la foto scrivendo il *nome* nella didascalia.")
      end

      # 1. Recupero file
      file_id = msg.photo.last.file_id
      file_info = bot.api.get_file(file_id: file_id)
      # Accediamo direttamente al metodo file_path dell'oggetto restituito
      url = "https://api.telegram.org/file/bot#{bot.api.token}/#{file_info.file_path}"
      local_path = "data/carte/temp_#{u_id}.png"
      # Assicuriamoci che la directory esista per evitare altri NoMethodError/Errno
      FileUtils.mkdir_p("data/carte") unless Dir.exist?("data/carte")

      File.open(local_path, "wb") do |f|
        f.write(Faraday.get(url).body)
      end

      # 2. Scansione con BarcodeScanner
      barcode = BarcodeScanner.scan_image(local_path)

      if barcode
        # 3. Creazione carta (usa il metodo che hai già in carte_fedelta.rb)
        CarteFedelta.add_card_from_photo(bot, u_id, caption, barcode[:data], local_path, barcode[:format])
      else
        bot.api.send_message(chat_id: u_id, text: "❌ Nessun codice a barre trovato. Prova una foto più vicina e nitida.")
      end

      File.delete(local_path) if File.exist?(local_path)
    end
  end

  def self.core_start(bot, context)
    bot.api.send_message(chat_id: context.chat_id, text: "🤖 **Bot Spesa Refactored**\nUsa `+` per aggiungere o `?` per cercare.")
  end

  def self.core_cleanup(bot, context)
    # Esempio di metodo protetto
    return unless context.user_id.to_s == "IL_TUO_ID_ADMIN"
    puts "[CORE] 🧹 Avvio Cleanup di sistema"
  end

  def self.handle_myitems(bot, chat_id, user_id, message, page = 0, show_all = false)
    is_callback = message.is_a?(Telegram::Bot::Types::CallbackQuery)
    real_message = is_callback ? message.message : message

    # 1. Recupero Dati tramite DataManager
    groups_and_topics = DataManager.prendi_gruppi_con_articoli(user_id, show_all)
    return if groups_and_topics.empty?

    conf = DataManager.carica_config_utente(user_id) || {}

    # 2. Configurazione Paginazione
    per_page = 5
    total_pages = (groups_and_topics.size.to_f / per_page).ceil
    page = [[page, 0].max, total_pages - 1].min
    slice = groups_and_topics.slice(page * per_page, per_page) || []

    title = show_all ? "📦 TUTTI GLI ARTICOLI" : "📋 I TUOI ARTICOLI"
    text = "<b>#{title}</b> (Pag. #{page + 1}/#{total_pages})\n"
    text << "<i>Clicca l'articolo per spuntare, il titolo per cambiare contesto.</i>\n\n"

    item_buttons = []

    # 3. Ciclo sui Gruppi/Topic
    slice.each do |row|
      g_id, t_id = row["gruppo_id"], row["topic_id"]
      is_active = (g_id == conf["db_id"].to_i && t_id == conf["topic_id"].to_i)

      # 1. Recupero dati grezzi (Hash solido senza istanziare Context)
      info = DataManager.recupera_nomi_contesto(g_id, t_id)

      # 2. Logica di formattazione identica a Context.nome_contesto_pulito
      if info[:nome] == "Privata"
        etichetta_contesto = info[:topic]
      elsif info[:topic] == "Generale" || info[:topic] == info[:nome]
        etichetta_contesto = info[:nome]
      else
        etichetta_contesto = "#{info[:nome]}: #{info[:topic]}"
      end

      prefix = is_active ? "🎯 " : "📂 "

      # Intestazione Gruppo/Topic
      item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{prefix}#{etichetta_contesto.upcase}",
        callback_data: "mycontext:#{g_id}:#{t_id}:#{show_all ? 1 : 0}",
      )]

      # 3. Articoli (Sempre con autore_init dalla JOIN)
      articoli = DataManager.prendi_articoli_per_storico(g_id, t_id, user_id, show_all)

      articoli.each do |art|
        status = (art["comprato"] && !art["comprato"].empty?) ? "✅" : "▫️"

        autore_tag = ""
        if show_all && g_id != 0
          tag = art["autore_init"] || "?"
          autore_tag = "[#{tag}] "
        end

        item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{status} #{autore_tag}#{art["nome"]}",
          callback_data: "mycomprato:#{art["id"]}:#{g_id}:#{t_id}:#{page}:#{show_all ? 1 : 0}",
        )]
      end
    end

    # 4. CREAZIONE PULSANTI DI NAVIGAZIONE
    nav_row = []
    if total_pages > 1
      if page > 0
        nav_row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️",
          callback_data: "myitems_page:#{user_id}:#{page - 1}:#{show_all ? 1 : 0}",
        )
      end

      nav_row << Telegram::Bot::Types::InlineKeyboardButton.new(text: "#{page + 1}/#{total_pages}", callback_data: "noop")

      if page < total_pages - 1
        nav_row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "▶️",
          callback_data: "myitems_page:#{user_id}:#{page + 1}:#{show_all ? 1 : 0}",
        )
      end
    end

    # Pulsanti di chiusura e refresh
    footer_row = [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "🔄", callback_data: "myitems_refresh:#{user_id}:#{page}:#{show_all ? 1 : 0}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{chat_id}:0"),
    ]

    # Composizione finale tastiera
    keyboard = item_buttons
    keyboard << nav_row unless nav_row.empty?
    keyboard << footer_row

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)

    if is_callback
      begin
        bot.api.edit_message_text(
          chat_id: chat_id,
          message_id: real_message.message_id,
          text: text,
          reply_markup: markup,
          parse_mode: "HTML",
        )
      rescue Telegram::Bot::Exceptions::ResponseError => e
        # Se il contenuto è identico, Telegram risponde con 400 "message is not modified"
        # Lo ignoriamo per evitare il RUNTIME ERROR
        raise e unless e.message.include?("message is not modified")
        puts "[DEBUG] Refresh ignorato: contenuto identico"
      end
    else
      bot.api.send_message(chat_id: chat_id, text: text, reply_markup: markup, parse_mode: "HTML")
    end
  end
end

# In message_handler.rb (aggiungi in fondo o come classe di supporto)

class TopicManager
  def self.sincronizza(msg)
    # LOG DI INGRESSO
    puts "[SYNC_LOG] 📨 Analisi messaggio ID:#{msg.message_id}"

    # CASO A: Cambio titolo del gruppo (Globale)
    if msg.new_chat_title
      puts "[SYNC_LOG] 🏢 Rilevato NEW_CHAT_TITLE: #{msg.new_chat_title}"
      DataManager.aggiorna_nome_gruppo(msg.chat.id, msg.new_chat_title)
      return
    end

    # CASO B: Cambio Topic (Forum)
    topic_name = nil
    if msg.forum_topic_created
      topic_name = msg.forum_topic_created.name
      puts "[SYNC_LOG] 🆕 Rilevato FORUM_TOPIC_CREATED: #{topic_name}"
    elsif msg.forum_topic_edited
      topic_name = msg.forum_topic_edited.name
      puts "[SYNC_LOG] ✏️ Rilevato FORUM_TOPIC_EDITED: #{topic_name}"
    end

    if topic_name
      t_id = (msg.respond_to?(:message_thread_id) && msg.message_thread_id) ? msg.message_thread_id : 0
      DataManager.set_topic_name(msg.chat.id, t_id, topic_name)
    else
      puts "[SYNC_LOG] ℹ️ Messaggio ignorato (nessun cambio titolo o topic rilevato)"
    end
  end
end
