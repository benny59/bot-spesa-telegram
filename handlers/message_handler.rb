# handlers/message_handler.rb
require_relative "../utils/keyboard_generator"
require_relative "../models/context"
require_relative "../models/group_manager"
require_relative "../models/group_operational_notifier"
require_relative "../models/carte_fedelta"
require_relative "../models/carte_fedelta_gruppo"
require_relative "./storico_manager"
require_relative "../db"
require_relative "./cleanup_manager"  # needed for /cleanup command

class MessageHandler
  # ==============================================================================
  # ROUTER PRINCIPALE (DISPATCHER)
  def self.ensure_group_registered!(msg, user_id = msg.from.id)
    return if msg.chat.nil? || msg.chat.id.to_i >= 0

    chat_id = msg.chat.id.to_i
    existing = DataManager.prendi_gruppo_da_chat_id(chat_id)
    return unless existing.nil? || existing.empty?

    if msg.respond_to?(:migrate_from_chat_id) && msg.migrate_from_chat_id.to_i != 0
      old_chat_id = msg.migrate_from_chat_id.to_i
      old_group = DataManager.prendi_gruppo_da_chat_id(old_chat_id)
      if old_group && !old_group.empty?
        DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [chat_id, old_group["id"]])
        DB.execute("UPDATE topics SET chat_id = ? WHERE chat_id = ?", [chat_id, old_chat_id])
        puts "🔄 [GROUP_MIGRATION] Rimosso ID vecchio #{old_chat_id} -> #{chat_id} per gruppo #{old_group['id']}"
        return
      end
    end

    nome_gruppo = msg.chat.title.to_s.strip.empty? ? "Gruppo #{chat_id}" : msg.chat.title.to_s.strip
    DataManager.registra_gruppo_se_nuovo(chat_id, nome_gruppo, user_id)
  end

  def self.route(bot, msg, context)
    u_id = msg.from.id
    c_id = msg.chat.id
    g_chat_id = msg.chat.id

    self.ensure_group_registered!(msg, u_id)

    raw_text = msg.text.to_s.strip
    text = raw_text.split("@").first # Prende solo "/newgroup" da "/newgroup@bot"


# --- STEP 1: GESTIONE INOLTRO ---
    if msg.forward_origin
      return self.handle_forward(bot, msg, context)
    end
# -------------------------------
        
    


    DataManager.aggiorna_membership(msg.from.id, msg.chat.id)

    # Estrazione dati per Whitelist e User_Names
    username = msg.from.username || "Unknown"
    first_name = msg.from.first_name || "Utente"
    last_name = msg.from.last_name || ""
    full_name = "#{first_name} #{last_name}".strip

    # --- CHIRURGIA: SPOSTIAMO QUI IL COMANDO ---
    if text == "/newgroup"
      return self.handle_newgroup(bot, msg, c_id, u_id)
    end

    # 0. CONTROLLO WHITELIST
    unless Whitelist.is_allowed?(u_id)
      Whitelist.add_pending_request(u_id, username, full_name)
      c_creator_id = Whitelist.get_creator_id
      if c_creator_id && c_creator_id != u_id
        self.notifica_creatore_nuovo_utente(bot, c_creator_id, u_id, username, full_name)
      end
      return bot.api.send_message(
               chat_id: msg.chat.id,
               text: "🚫 *Accesso Limitato*\nLa tua richiesta (ID: #{u_id}) è in attesa di approvazione.",
               parse_mode: "Markdown",
             )
    end

    Whitelist.salva_nome_utente(u_id, first_name, last_name)

    # 1. Tenta il caricamento della config salvata
    config_salvata = DataManager.carica_config_utente(u_id)

    # 2. SE config_salvata è nil, creiamo un hash di default basato sul gruppo attuale
    if config_salvata.nil? || config_salvata.empty?
      # Usa il tuo metodo già esistente in db.rb
      gruppo_row = DataManager.prendi_gruppo_da_chat_id(msg.chat.id)

      g_id_auto = gruppo_row ? gruppo_row["id"].to_i : 0
      t_id_auto = msg.respond_to?(:message_thread_id) ? (msg.message_thread_id || 0) : 0

      config_salvata = { "db_id" => g_id_auto, "topic_id" => t_id_auto }
      puts "🔄 [AUTO-ADAPT] Config generata per #{u_id} -> G:#{g_id_auto}"
    end

    # 3. FIX CRASH: Se l'oggetto config nel contesto è nil, dobbiamo inizializzarlo
    # Usiamo l'istanza per bypassare il problema del nil su attr_reader
    if context.config.nil?
      context.instance_variable_set(:@config, {})
    end

    # 4. Ora puoi popolare senza errori
    context.config["db_id"] = config_salvata["db_id"].to_i
    context.config["topic_id"] = config_salvata["topic_id"].to_i

    effective_g_id = context.config["db_id"].to_i
    effective_t_id = context.config["topic_id"].to_i




    # --- GESTIONE FOTO ---
    if msg.photo && !msg.photo.empty?
      puts "[TRACE_PHOTO] 🖼️ Foto rilevata. Caption: '#{msg.caption}'"
      pending = DataManager.ottieni_pending(c_id, effective_t_id)

      if pending && pending["action"]&.start_with?("add:")
        puts "[TRACE_PHOTO] 🎯 MATCH! Procedo al salvataggio..."
        begin
          testo = msg.caption || "Articolo da foto"
          g_id = pending["gruppo_id"].to_i
          t_id = effective_t_id

          ids = DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: u_id, items_text: testo, topic_id: t_id)

          if ids.any?
            ids.each { |id| DataManager.salva_foto_articolo(id, msg.photo.last.file_id, msg.photo.last.file_unique_id) }
            DataManager.rimuovi_pending(c_id, t_id)

            if context.scope == :private && g_id != 0
              real_chat_id = DataManager.get_real_chat_id(g_id)
              if real_chat_id
                # Usiamo il metodo che hai già in DataManager per recuperare i dati dell'utente
                # Se non hai un metodo 'get_initials', usiamo quello che carica gli articoli
                # e prendiamo l'iniziale dall'autore, che è la cosa più sicura.
                articoli_freschi = DataManager.prendi_articoli_ordinati(g_id, t_id)
                mio_item = articoli_freschi.find { |i| i["creato_da"] == u_id }
                init = mio_item ? mio_item["autore_init"] : "??"

                GroupOperationalNotifier.notify(
                  bot: bot,
                  gruppo_id: g_id,
                  topic_id: t_id,
                  text: "📸 <b>#{init}</b> ha aggiunto una foto: <b>#{testo}</b>",
                  disable_notification: true
                )
              end
            end

            # 4. CONFERMA IN PRIVATO (L' "OK" che mancava)
            bot.api.send_message(
              chat_id: context.chat_id,
              text: "✅ Ho aggiunto <b>#{testo}</b> con la foto alla lista.",
              parse_mode: "HTML",
            )
          end
        rescue => e
          puts "[TRACE_PHOTO] ❌ ERRORE: #{e.message}"
        end
        return
      elsif context.private_chat? && msg.caption && !msg.caption.empty?
        # Bridge per caricamento carte fedeltà
        return self.handle_photo_bridge(bot, msg, context)
      end
    end

    # --- LOGICA ROUTING ---
    unless context.private_chat?
      TopicManager.sincronizza(msg)
      gruppo = DataManager.prendi_gruppo_da_chat_id(g_chat_id)
      context.config["db_id"] = gruppo ? gruppo["id"].to_i : 0
      t_id_msg = msg.respond_to?(:message_thread_id) ? msg.message_thread_id : nil
      context.config["topic_id"] = t_id_msg ? t_id_msg.to_i : 0
    else
      config_salvata = DataManager.carica_config_utente(u_id) || {}
      g_id = config_salvata["db_id"] || config_salvata["target_g"]
      t_id = config_salvata["topic_id"] || config_salvata["target_t"]
      context.config["db_id"] = (g_id || 0).to_i
      context.config["topic_id"] = (t_id || 0).to_i
    end

    DataManager.salva_config_utente(u_id, context.config)

    case text

    when %r{^/(quiet|verbose)(?:@\w+)?$}
      command = Regexp.last_match(1)
      unless context.group_chat?
        bot.api.send_message(chat_id: c_id, text: "⚠️ Questo comando funziona solo all'interno di un gruppo.")
        return
      end

      gruppo = GroupManager.find_by_chat_id(c_id)
      unless gruppo
        bot.api.send_message(chat_id: c_id, text: "⚠️ Questo gruppo non è ancora registrato.")
        return
      end

      unless GroupManager.admin_del_gruppo?(bot, c_id, u_id)
        bot.api.send_message(chat_id: c_id, text: "⛔ Solo un amministratore del gruppo può modificare le notifiche operative.")
        return
      end

      abilitate = command == "verbose"
      GroupManager.imposta_notifiche_operazioni(gruppo["id"], abilitate)
      bot.api.send_message(
        chat_id: c_id,
        message_thread_id: (context.config["topic_id"].to_i > 0 ? context.config["topic_id"].to_i : nil),
        text: abilitate ? "🔔 Notifiche operative riattivate in questo gruppo." : "🔕 Notifiche operative disattivate in questo gruppo."
      )
      return

    when "/cleanup"
      puts "🔧 comando /cleanup ricevuto da #{u_id}"
      CleanupManager.esegui_cleanup(bot, msg.chat.id, u_id)
      puts "🔧 cleanup eseguito (ritorno al router)"
      return
    
  when "/ss", "/share"
  # Recuperiamo l'ID del gruppo dal contesto (gestisce già privata vs gruppo)
  g_id = context.config["db_id"].to_i
  t_id = context.config["topic_id"].to_i

  if g_id == 0
    # Caso Lista Personale
    gruppo_obj = { "id" => 0, "nome" => "Personale" }
    self.handle_share_text(bot, msg, gruppo_obj, 0)
  else
    # Caso Lista Condivisa: recuperiamo i dati reali del gruppo dal DB
    # Usiamo un metodo esistente per avere l'hash del gruppo (id, nome, etc)
    gruppo_obj = DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [g_id])
    
    if gruppo_obj
      self.handle_share_text(bot, msg, gruppo_obj, t_id)
    else
      bot.api.send_message(chat_id: msg.chat.id, text: "⚠️ Errore: Gruppo #{g_id} non trovato.")
    end
  end  
    
    when /^\/(start|help)/
      self.core_start(bot, context)
      KeyboardGenerator.show_private_keyboard(bot, context.chat_id, context) if context.private_chat?
when "/setup_pin"
  # 1. Recupero ID Gruppo dal contesto
  g_id = context.config["db_id"].to_i
  t_id = context.config["topic_id"].to_i

  # 2. FALLBACK: Se siamo in un gruppo ma g_id è 0, recuperiamolo dal chat_id reale
  if g_id == 0 && msg.chat.id < 0
    gruppo_db = DataManager.prendi_gruppo_da_chat_id(msg.chat.id)
    g_id = gruppo_db["id"] if gruppo_db
  end

  # 3. Costruzione Tastiera con salvataggio (usiamo || 0 per evitare i "::")
  kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(
    text: "🛒 MOSTRA LISTA AGGIORNATA", 
    callback_data: "trigger_list:#{g_id || 0}:#{t_id || 0}"
  )]]

  # 4. Invio e Pin
  begin
    sent = bot.api.send_message(
      chat_id: msg.chat.id, 
      message_thread_id: (msg.chat.id < 0 && t_id > 0 ? t_id : nil), 
      text: "📌 <b>Pannello Spesa</b>\nUtilizza il tasto sotto per visualizzare la lista sempre aggiornata in questo reparto.", 
      reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb), 
      parse_mode: "HTML"
    )
    bot.api.pin_chat_message(chat_id: msg.chat.id, message_id: sent.message_id)
  rescue => e
    puts "❌ Errore durante setup_pin: #{e.message}"
    bot.api.send_message(chat_id: msg.chat.id, text: "⚠️ Non posso fissare il messaggio. Assicurati che io sia amministratore.")
  end
      when /^\/checklist/
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      kb = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)
      bot.api.send_message(chat_id: context.chat_id, message_thread_id: (t_id > 0 ? t_id : nil), text: "📋 *Checklist Intelligente*", reply_markup: kb, parse_mode: "Markdown") if kb
    when "/collegaapp"
      require 'securerandom'
      pin = "%06d" % SecureRandom.random_number(1_000_000)
      DB.execute("DELETE FROM link_pins WHERE user_id = ?", [u_id])
      DB.execute(
        "INSERT INTO link_pins (pin, user_id, first_name) VALUES (?, ?, ?)",
        [pin, u_id, msg.from.first_name.to_s]
      )
      bot.api.send_message(
        chat_id: u_id,
        text: "🔗 *Codice collegamento app*\n\n`#{pin}`\n\nInseriscilo nell'app entro 10 minuti.\n_Ogni volta che usi /collegaapp il codice precedente viene invalidato._",
        parse_mode: "Markdown"
      )
    when "/addcartagruppo"
      if g_chat_id < 0
        gruppo = DataManager.prendi_gruppo_da_chat_id(g_chat_id)
        CarteFedeltaGruppo.show_add_to_group_interface(bot, u_id, gruppo["id"], nil) if gruppo
      end
    when "/carte", "/cartegruppo"
      CarteFedeltaGruppo.show_group_cards(bot, context.config["db_id"], g_chat_id, u_id, context.config["topic_id"])
    when "💳 LE MIE CARTE"
      CarteFedelta.mostra_personali(bot, u_id)
    when "/lista"
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)
      self.core_mostra_lista(bot, context, items, header, g_id, t_id, 0)
    when /^\?(.*)/
      # 1. NON ricalcolare nulla. Usa il contesto già pronto!
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i

      # 2. Prendi i dati usando il metodo "buono" che vede le foto
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)

      # 3. Mostra la lista
      self.core_mostra_lista(bot, context, items, header, g_id, t_id, 0)
    when "/tutti", "📦 TUTTI GLI ARTICOLI"
      self.handle_myitems(bot, context.chat_id, u_id, msg, 0, true)
    when "/miei", "📋 I MIEI ARTICOLI"
      self.handle_myitems(bot, context.chat_id, u_id, msg, 0, false)
    when /^🛒 LISTA/
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      # USARE SEMPRE QUESTO:
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)
      self.core_mostra_lista(bot, context, items, header, g_id, t_id)
    when "/private", "⚙️ IMPOSTA GRUPPO"
      KeyboardGenerator.show_group_selector(bot, u_id)
    when "➕ AGGIUNGI PRODOTTO"
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      DataManager.set_pending(chat_id: c_id, topic_id: t_id, action: "add:#{first_name}", gruppo_id: g_id)
      bot.api.send_message(chat_id: c_id, text: "✍️ <b>#{first_name}</b>, scrivi gli articoli o manda una foto.", parse_mode: "HTML")
    when /^\+(.*)/
      self.core_aggiunta(bot, context, $1.to_s.strip, false, msg)
    when /^\*(.*)/
      self.core_aggiunta(bot, context, $1.to_s.strip, true, msg)
    else
      t_id_logico = context.config["topic_id"].to_i
      self.handle_pending_responses(bot, msg, context, t_id_logico)
    end
  end

  # ==============================================================================
  # FUNZIONI CORE
  # ==============================================================================

  def self.core_mostra_lista(bot, context, items, header, g_id, t_id, page = 0)
    options = {
      nome_target: header,
      is_group: !context.private_chat?, # Sfruttiamo il metodo che hai già nel context
    }
    ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, options)
    target_thread = context.private_chat? ? nil : (t_id.to_i > 0 ? t_id.to_i : nil)
    bot.api.send_message(chat_id: context.chat_id, message_thread_id: target_thread, text: ui[:text], reply_markup: ui[:markup], parse_mode: "HTML")
  end

def self.core_aggiunta(bot, context, contenuto, force_personal = false, msg = nil)
  u_id = context.user_id
  u_name = msg ? msg.from.first_name : "Utente"
  testo_pulito = contenuto.to_s.gsub(/^[\+\*]/, "").strip

  return if testo_pulito.empty? # (Logica pending omessa per brevità)

  g_id = force_personal ? 0 : context.config["db_id"].to_i
  t_id = force_personal ? 0 : context.config["topic_id"].to_i

  # Recupero nome lista dal metodo esistente
  info_contesto = DataManager.recupera_nomi_contesto(g_id, t_id)
  nome_lista = info_contesto[:nome]

  DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: u_id, items_text: contenuto, topic_id: t_id)

  # Notifica al gruppo (Aggiunta da privata)
  if context.scope == :private && g_id != 0
    GroupOperationalNotifier.notify(
      bot: bot,
      gruppo_id: g_id,
      topic_id: t_id,
      text: "➕ <b>#{u_name}</b> ha aggiunto: #{testo_pulito}",
      disable_notification: true
    )
  end

  # Conferma nel thread corretto: nel gruppo/tema corrente, non nel generale
  bot.api.send_message(
    chat_id: context.chat_id,
    message_thread_id: (t_id > 0 ? t_id : nil),
    text: "✅ <b>#{testo_pulito}</b> aggiunto alla lista <b>#{nome_lista}</b>.",
    parse_mode: "HTML"
  )
end

def self.handle_share_text(bot, msg, gruppo, topic_id)
  g_id = gruppo["id"]
  t_id = topic_id.to_i
  
  # Recupero dati consolidati
  items = DataManager.prendi_articoli_ordinati(g_id, t_id)
  info = DataManager.recupera_nomi_contesto(g_id, t_id)

  # Filtro: teniamo solo gli articoli NON comprati
  da_comprare = items.reject { |i| i["deleted"].to_i == 1 || (i["comprato"] && !i["comprato"].empty?) }

  if da_comprare.empty?
    bot.api.send_message(
      chat_id: msg.chat.id,
      message_thread_id: (msg.chat.id < 0 ? t_id : nil),
      text: "📝 Nessun articolo da comprare nella lista <b>#{info[:nome]}</b>.",
      parse_mode: "HTML"
    )
    return
  end

  # Costruzione messaggio
  testo = "🛒 <b>LISTA SPESA: #{info[:nome].upcase}</b>\n"
  testo += "📍 <b>Reparto:</b> #{info[:topic]}\n\n"

  da_comprare.each do |item|
    testo += "▫️ <b>#{item['nome']}</b>\n"
  end

  # Chiusura asciutta con timestamp
  testo += "\n" + "—" * 15
  testo += "\n<i>Aggiornato il: #{Time.now.strftime("%d/%m/%Y alle %H:%M")}</i>"

  bot.api.send_message(
    chat_id: msg.chat.id,
    message_thread_id: (msg.chat.id < 0 ? t_id : nil),
    text: testo,
    parse_mode: "HTML"
  )
end


  def self.handle_pending_responses(bot, msg, context, forced_t_id = nil)
    t_id = forced_t_id || context.topic_id || 0
    pending = DataManager.ottieni_pending(context.chat_id, t_id)
    if pending && pending["action"]&.start_with?("add")
      self.core_aggiunta(bot, context, msg.text, false, msg)
      DataManager.rimuovi_pending(context.chat_id, t_id)
    end
  end

  def self.handle_photo_bridge(bot, msg, context)
    u_id = msg.from.id
    caption = msg.caption.to_s.strip
    file_id = msg.photo.last.file_id
    file_info = bot.api.get_file(file_id: file_id)
    url = "https://api.telegram.org/file/bot#{bot.api.token}/#{file_info.file_path}"
    local_path = "data/carte/temp_#{u_id}.png"
    FileUtils.mkdir_p("data/carte")
    File.open(local_path, "wb") { |f| f.write(Faraday.get(url).body) }

    barcode = BarcodeScanner.scan_image(local_path)
    if barcode
      CarteFedelta.add_card_from_photo(bot, u_id, caption, barcode[:data], local_path, barcode[:format])
    else
      bot.api.send_message(chat_id: u_id, text: "❌ Nessun codice a barre trovato.")
    end
    File.delete(local_path) if File.exist?(local_path)
  end

  def self.handle_myitems(bot, chat_id, user_id, message, page = 0, show_all = false)
    puts "🔍 [DEBUG HANDLE] Entrato per U:#{user_id} | ShowAll:#{show_all}"
    is_callback = message.is_a?(Telegram::Bot::Types::CallbackQuery)
    real_message = is_callback ? message.message : message
    groups_and_topics = DataManager.prendi_gruppi_con_articoli(user_id, show_all)
    title = show_all ? "📦 TUTTI GLI ARTICOLI" : "📋 I MIEI ARTICOLI"

    puts "🔍 [DEBUG HANDLE] Gruppi trovati: #{groups_and_topics.size}"
    if groups_and_topics.any?
      # Stampiamo il primo per vedere se contiene ancora articoli completati
      puts "🔍 [DEBUG HANDLE] Esempio Gruppo: #{groups_and_topics.first["nome"]} | ID: #{groups_and_topics.first["id"]}"
    end

    if groups_and_topics.empty?
      text = "<b>#{title}</b>\n\n✅ Lista pulita! Non ci sono articoli completati."
      if is_callback
        bot.api.edit_message_text(chat_id: chat_id, message_id: real_message.message_id, text: text, parse_mode: "HTML") rescue nil
      else
        bot.api.send_message(chat_id: chat_id, text: text, parse_mode: "HTML")
      end
      return # Esce dopo aver pulito l'interfaccia
    end

    conf = DataManager.carica_config_utente(user_id) || {}
    per_page = 5
    total_pages = (groups_and_topics.size.to_f / per_page).ceil
    page = [[page, 0].max, total_pages - 1].min
    slice = groups_and_topics.slice(page * per_page, per_page) || []

    text = "<b>#{title}</b> (Pag. #{page + 1}/#{total_pages})\n"

    # CHIAMATA AL GENERATORE ESTERNO
    markup = KeyboardGenerator.markup_lista_globale(user_id, slice, conf, page, total_pages, show_all, chat_id)

    if is_callback
      bot.api.edit_message_text(chat_id: chat_id, message_id: real_message.message_id, text: text, reply_markup: markup, parse_mode: "HTML") rescue nil
    else
      bot.api.send_message(chat_id: chat_id, text: text, reply_markup: markup, parse_mode: "HTML")
    end
  end

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
  
def self.handle_forward(bot, msg, context)
    u_id = msg.from.id
    origin = msg.forward_origin

    # 1. Recupero dati e censimento
    if origin.type == 'user'
      f_id   = origin.sender_user.id
      f_name = origin.sender_user.first_name || "Utente"
      f_last = origin.sender_user.last_name || ""
    else
      return puts "⚠️ [FORWARD] Origine non supportata."
    end

    DataManager.registra_utente(f_id, f_name, f_last)
    res = DB.get_first_row("SELECT initials FROM user_names WHERE user_id = ?", [f_id])
    iniziali = res ? res["initials"] : "??"

    # 2. TRASFORMAZIONE LISTA (Uso delle parentesi quadre [])
    raw_items = msg.text.to_s.split(/,|\n/)
    
    processed_text = raw_items.map do |item| 
      item_pulito = item.strip
      next if item_pulito.empty?
      # USIAMO LE QUADRE PER EVITARE ERRORI DI PARSING HTML
      "(#{iniziali}) #{item_pulito}"
    end.compact.join(", ")

    # 3. MEMORIZZAZIONE
    puts "🚀 [FORWARD_PROCESS] Aggiunta articoli per conto di [#{iniziali}]: #{processed_text}"
    
    # Chiamiamo il tuo metodo esistente
    self.core_aggiunta(bot, context, processed_text, false, msg)
  end
  
          

  def self.handle_newgroup_approved(bot, msg, chat_id, user_id)
    nome_gruppo = msg.chat.title || "Lista di #{msg.from.first_name}"

    # Chiamata pulita al DataManager
    risultato = DataManager.registra_gruppo_se_nuovo(chat_id, nome_gruppo, user_id)

    case risultato[:status]
    when :esistente
      bot.api.send_message(
        chat_id: chat_id,
        text: "ℹ️ **Gruppo già presente**\nQuesto gruppo è già registrato con l'ID: `#{risultato[:id]}`.",
        parse_mode: "Markdown",
      )
    when :creato
      bot.api.send_message(
        chat_id: chat_id,
        text: "🎉 **Gruppo registrato!**\n🆔 ID Interno: `#{risultato[:id]}`\nOra puoi usare i comandi della lista.",
        parse_mode: "Markdown",
      )
    when :errore
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore durante la registrazione: #{risultato[:messaggio]}")
    end
  end

  def self.core_start(bot, context)
    bot.api.send_message(chat_id: context.chat_id, text: "🤖 **Bot Spesa**\nUsa `+` per aggiungere o `?` per cercare.")
  end

  def self.notifica_creatore_nuovo_utente(bot, creator_id, user_id, username, full_name)
    clean_name = full_name.gsub(/\s+/, "_")
    kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(text: "✅ Approva", callback_data: "adm_app:#{user_id}:#{username}:#{clean_name}"),
           Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Rifiuta", callback_data: "adm_rej:#{user_id}")]]
    bot.api.send_message(chat_id: creator_id, text: "🔔 **Richiesta Accesso**\n👤 #{full_name}\n🆔 #{user_id}", reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb), parse_mode: "HTML")
  end
end

class TopicManager
  def self.sincronizza(msg)
    if msg.new_chat_title
      DataManager.aggiorna_nome_gruppo(msg.chat.id, msg.new_chat_title)
    elsif msg.forum_topic_created
      DataManager.set_topic_name(msg.chat.id, msg.message_thread_id, msg.forum_topic_created.name)
    elsif msg.forum_topic_edited
      DataManager.set_topic_name(msg.chat.id, msg.message_thread_id, msg.forum_topic_edited.name)
    end
  end
end
