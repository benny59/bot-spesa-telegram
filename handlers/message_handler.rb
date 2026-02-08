# handlers/message_handler.rb
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
    c_id = msg.chat.id
    g_chat_id = msg.chat.id

    raw_text = msg.text.to_s.strip
    text = raw_text.split("@").first # Prende solo "/newgroup" da "/newgroup@bot"
    
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

    # Caricamento contesto forzato
    if context.config["db_id"].nil?
      config_salvata = DataManager.carica_config_utente(u_id) || {}
      context.config["db_id"] = (config_salvata["db_id"] || config_salvata["target_g"] || 0).to_i
      context.config["topic_id"] = (config_salvata["topic_id"] || config_salvata["target_t"] || 0).to_i
    end

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

                bot.api.send_message(
                  chat_id: real_chat_id,
                  message_thread_id: (t_id > 0 ? t_id : nil),
                  text: "📸 <b>#{init}</b> ha aggiunto una foto: <b>#{testo}</b>",
                  parse_mode: "HTML",
                  disable_notification: true,
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
    when /^\/(start|help)/
      self.core_start(bot, context)
      KeyboardGenerator.show_private_keyboard(bot, context.chat_id, context) if context.private_chat?
    when "/setup_pin"
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      kb = [[Telegram::Bot::Types::InlineKeyboardButton.new(text: "🛒 MOSTRA LISTA AGGIORNATA", callback_data: "trigger_list:#{g_id}:#{t_id}")]]
      sent = bot.api.send_message(chat_id: msg.chat.id, message_thread_id: (t_id > 0 ? t_id : nil), text: "📌 <b>Pannello Spesa</b>", reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb), parse_mode: "HTML")
      bot.api.pin_chat_message(chat_id: msg.chat.id, message_id: sent.message_id)
    when /^\/checklist/
      g_id = context.config["db_id"].to_i
      t_id = context.config["topic_id"].to_i
      kb = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)
      bot.api.send_message(chat_id: context.chat_id, message_thread_id: (t_id > 0 ? t_id : nil), text: "📋 *Checklist Intelligente*", reply_markup: kb, parse_mode: "Markdown") if kb
    when "/addcartagruppo"
      if g_chat_id < 0
        gruppo = DataManager.prendi_gruppo_da_chat_id(g_chat_id)
        CarteFedeltaGruppo.show_add_to_group_interface(bot, u_id, gruppo["id"], nil) if gruppo
      end
    when "/carte", "/cartegruppo"
      CarteFedeltaGruppo.show_group_cards(bot, context.config["db_id"], g_chat_id, u_id, context.config["topic_id"])
    when "💳 LE MIE CARTE"
      CarteFedelta.mostra_personali(bot, u_id)
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

    if testo_pulito.empty?
      g_pending = force_personal ? 0 : context.config["db_id"].to_i
      t_pending = force_personal ? 0 : context.config["topic_id"].to_i
      DataManager.set_pending(chat_id: context.chat_id, topic_id: t_pending, action: "add:#{u_name}", gruppo_id: g_pending)
      bot.api.send_message(chat_id: context.chat_id, message_thread_id: (context.chat_id < 0 ? t_pending : nil), text: "✍️ <b>#{u_name}</b>, scrivi gli articoli o manda una foto.", parse_mode: "HTML")
      return
    end

    g_id = force_personal ? 0 : context.config["db_id"].to_i
    t_id = force_personal ? 0 : context.config["topic_id"].to_i
    DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: u_id, items_text: contenuto, topic_id: t_id)

    items = DataManager.prendi_articoli_ordinati(g_id, t_id)
    if context.scope == :private && g_id != 0
      real_chat_id = DataManager.get_real_chat_id(g_id)
      if real_chat_id
        mio_item = items.find { |i| i["creato_da"] == u_id }
        init = mio_item ? mio_item["autore_init"] : u_name[0..1].upcase
        bot.api.send_message(chat_id: real_chat_id, message_thread_id: (t_id > 0 ? t_id : nil), text: "➕ <b>#{u_name}</b> ha aggiunto: #{testo_pulito}", parse_mode: "HTML", disable_notification: true)
      end
    end

    bot.api.send_message(chat_id: context.chat_id, message_thread_id: (context.private_chat? ? nil : t_id), text: "✅ <b>#{testo_pulito}</b> aggiunto alla lista.", parse_mode: "HTML")
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
    is_callback = message.is_a?(Telegram::Bot::Types::CallbackQuery)
    real_message = is_callback ? message.message : message
    groups_and_topics = DataManager.prendi_gruppi_con_articoli(user_id, show_all)
    return if groups_and_topics.empty?

    conf = DataManager.carica_config_utente(user_id) || {}
    per_page = 5
    total_pages = (groups_and_topics.size.to_f / per_page).ceil
    page = [[page, 0].max, total_pages - 1].min
    slice = groups_and_topics.slice(page * per_page, per_page) || []

    title = show_all ? "📦 TUTTI GLI ARTICOLI" : "📋 I MIEI ARTICOLI"
    text = "<b>#{title}</b> (Pag. #{page + 1}/#{total_pages})\n"
    item_buttons = []

    slice.each do |row|
      g_id, t_id = row["gruppo_id"], row["topic_id"]
      is_active = (g_id == conf["db_id"].to_i && t_id == conf["topic_id"].to_i)
      info = DataManager.recupera_nomi_contesto(g_id, t_id)
      label = info[:nome] == "Privata" ? info[:topic] : (info[:topic] == "Generale" ? info[:nome] : "#{info[:nome]}: #{info[:topic]}")
      prefix = is_active ? "🎯 " : "📂 "

      item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "#{prefix}#{label.upcase}", callback_data: "mycontext:#{g_id}:#{t_id}:#{show_all ? 1 : 0}")]
      DataManager.prendi_articoli_per_storico(g_id, t_id, user_id, show_all).each do |art|
        status = (art["comprato"] && !art["comprato"].empty?) ? "✅" : "▫️"
        tag = (show_all && g_id != 0) ? "[#{art["autore_init"] || "?"}] " : ""

        icona_foto = (art["ha_foto_reale"].to_i > 0) ? " 📸" : ""
        label_articolo = "#{status} #{tag}#{art["nome"]}#{icona_foto}"

        item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(
          text: label_articolo,
          callback_data: "myallcomprato:#{art["id"]}:#{g_id}:#{t_id}:#{page}:#{show_all ? 1 : 0}",
        )]
      end
    end

    nav = []
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "◀️", callback_data: "myitems_page:#{user_id}:#{page - 1}:#{show_all ? 1 : 0}") if page > 0
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "▶️", callback_data: "myitems_page:#{user_id}:#{page + 1}:#{show_all ? 1 : 0}") if page < total_pages - 1

    keyboard = item_buttons
    keyboard << nav unless nav.empty?
    keyboard << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "🔄", callback_data: "myitems_refresh:#{user_id}:#{page}:#{show_all ? 1 : 0}"), Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{chat_id}:0")]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
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
