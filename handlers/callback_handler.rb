# handlers/callback_handler.rb
require_relative "storico_manager"
require_relative "../models/carte_fedelta"
require_relative "../models/whitelist"

require_relative "../models/context"
require_relative "../db"

class CallbackHandler
  def self.route(bot, callback, context)
    data = callback.data
    user_id = callback.from.id
    user_name = callback.from.first_name
    bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil
    puts "[CALLBACK] 🖱️ Ricevuto: '#{data}' da #{user_name}"

    case data
    # In CallbackHandler (o nel blocco case del callback in bot_spesa.rb)
    when /^adm_app:(\d+):(.+):(.+)$/
      target_id, target_user, target_name = $1.to_i, $2, $3.gsub("_", " ")
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "✅ Utente approvato!")

      # ✅ Azione su DB: Approva l'utente
      Whitelist.approve_user(target_id, target_user, target_name)

      bot.api.edit_message_text(
        chat_id: callback.message.chat.id,
        message_id: callback.message.message_id,
        text: "✅ <b>Richiesta Approvata</b>\nL'utente #{target_name} è ora in whitelist.",
        parse_mode: "HTML",
      )
      # Notifica l'utente interessato
      bot.api.send_message(chat_id: target_id, text: "🎉 La tua richiesta è stata approvata!")
    when /^adm_rej:(\d+)$/
      target_id = $1.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "❌ Richiesta rifiutata")

      Whitelist.remove_pending_request(target_id)

      bot.api.edit_message_text(
        chat_id: callback.message.chat.id,
        message_id: callback.message.message_id,
        text: "❌ <b>Richiesta Rifiutata</b>\nL'utente ID #{target_id} è stato rimosso dai pendenti.",
        parse_mode: "HTML",
      )
    when /^mostra_carte:(\d+):(\d+)$/
      gruppo_id = $1.to_i
      topic_id = $2.to_i
      # Chiama il metodo che genera la tastiera con le tessere del gruppo
      CarteFedeltaGruppo.show_group_cards(bot, gruppo_id, callback.message.chat.id, callback.from.id, topic_id)
      # Rispondi al callback per togliere l'orologio dal bottone
      bot.api.answer_callback_query(callback_query_id: callback.id)
    when /^carte_gruppo_/
      # Delega tutto a CarteFedeltaGruppo che ha già la logica pronta
      CarteFedeltaGruppo.handle_callback(bot, callback)
    when /^carte:(\d+):(\d+)$/
      owner_id, card_id = $1.to_i, $2.to_i
      chat_id = callback.message.chat.id
      user_id = callback.from.id
      t_id = (callback.message.respond_to?(:message_thread_id) ? callback.message.message_thread_id : 0).to_i

      begin
        # 🎯 CHIAMATA UNICA: Non serve più IF/ELSE o g_id.
        # Il metodo mostra_singola_carta gestirà i permessi e il thread.
        puts "[DEBUG-CARTE] 🔍 Richiesta Visualizzazione | U:#{user_id} | Carta:#{card_id} | Topic:#{t_id}"

        CarteFedelta.mostra_singola_carta(bot, chat_id, owner_id, card_id, t_id)

        bot.api.answer_callback_query(callback_query_id: callback.id)
      rescue => e
        puts "❌ [RUNTIME ERROR CARTE] #{e.message}"
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "⚠️ Errore: #{e.message}")
      end
    when "close_barcode"
      bot.api.answer_callback_query(callback_query_id: callback.id)
      bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id) rescue nil

      # FIX: Aggiunto alias per la chiusura specifica delle carte se usata
    when /^carte_chiudi:(-?\d+):(\d+)$/
      bot.api.answer_callback_query(callback_query_id: callback.id)
      bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id) rescue nil
    when /^carte_confirm_delete:(\d+)$/
      bot.api.answer_callback_query(callback_query_id: callback.id)

      CarteFedelta.delete_card(bot, context.user_id, $1.to_i)
    when "carte_cancel_delete"
      bot.api.answer_callback_query(callback_query_id: callback.id)

      bot.api.delete_message(chat_id: context.chat_id, message_id: callback.message.message_id)
      # Nel blocco 'when' che gestisce i callback
    when /^ui_cards:(\d+):(\d+)$/
      g_id = $1.to_i
      t_id = $2.to_i

      # Chiamiamo il metodo che ora userà DataManager.carte_disponibili_nel_gruppo(g_id)
      # Passiamo g_id esplicito per non farlo cercare a caso nel context
      bot.api.answer_callback_query(callback_query_id: callback.id)
      CarteFedeltaGruppo.show_group_cards(bot, g_id, context.chat_id, user_id, t_id)
    when /^ui_page:(\d+):(\d+):(\d+)$/
      g_id, t_id, page = $1.to_i, $2.to_i, $3.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id)

      # Questo metodo fa già tutto (DB query + Keyboard + API Edit)
      self.refresh_ui(bot, callback, context, g_id, t_id, page, 0)

      # --------------------------------------------------------------------------
      # GESTIONE RITORNO ALLA LISTA (Fix per il tasto Indietro)
      # --------------------------------------------------------------------------
      # In handlers/callback_handler.rb

when /^trigger_list:(-?\d*):(\d*)$/
# ✅ CHIUDI SUBITO IL CALLBACK
  bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil
  g_id = $1.empty? ? context.config["db_id"].to_i : $1.to_i
  t_id = $2.empty? ? context.config["topic_id"].to_i : $2.to_i
  
  # Se ancora non abbiamo un g_id valido, proviamo a recuperarlo dal chat_id
  if g_id == 0 && callback.message.chat.id < 0
    g_id = DataManager.prendi_gruppo_da_chat_id(callback.message.chat.id)&.[]("id") || 0
  end

  puts "DEBUG: Trigger List recuperato -> G:#{g_id} T:#{t_id}"
  
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)

      # Costruiamo l'hash delle opzioni al volo
      options = {
        nome_target: header,
        is_group: !context.private_chat?,
      }

      # Passiamo l'hash invece della semplice stringa
      ui = KeyboardGenerator.genera_lista(items, g_id, t_id, 0, options)

      bot.api.send_message(
        chat_id: context.chat_id,
        message_thread_id: (t_id > 0 ? t_id : nil),
        text: ui[:text],
        reply_markup: ui[:markup],
        parse_mode: "HTML",
      )

    when /^myitems_refresh:(\d+):(\d+):(\d)$/
      u_id, page, s_all = $1.to_i, $2.to_i, $3.to_i
      show_all = (s_all == 1)

      # Feedback visivo per far capire che il bot sta lavorando
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🔄 Aggiornamento lista...")

      # Chiamata al metodo di classe per rigenerare la UI
      MessageHandler.handle_myitems(
        bot,
        callback.message.chat.id,
        u_id,
        callback,
        page,
        show_all
      )
    when /^show_storico:(\d+):(\d+)$/
      gruppo_id = $1.to_i
      topic_id = $2.to_i

      # 1. Creiamo l'istanza di contesto dal callback
      # Questo imposta correttamente @scope leggendo il tipo di chat (private/group)
      ctx = Context.from_callback(callback)

      # Recupero e formattazione dati
      acquisti = StoricoManager.ultimi_acquisti(gruppo_id, topic_id)
      testo = StoricoManager.formatta_storico(acquisti)

      current_chat_id = callback.message.chat.id

      # 2. Ora puoi usare il metodo di istanza correttamente
      # Se è una chat privata, target_thread sarà nil, evitando l'errore 400
      target_thread = ctx.private_chat? ? nil : (topic_id > 0 ? topic_id : nil)

      # Debug per verifica
      puts "🔍 Scope: #{ctx.scope} | Private?: #{ctx.private_chat?} | Target Thread: #{target_thread.inspect}"

      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [[
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Chiudi",
            callback_data: "ui_close:#{current_chat_id}:#{topic_id}",
          ),
        ]],
      )

      bot.api.send_message(
        chat_id: current_chat_id,
        message_thread_id: target_thread,
        text: testo,
        parse_mode: "Markdown",
        reply_markup: keyboard,
      )

      bot.api.answer_callback_query(callback_query_id: callback.id)
    when /^mycontext:(\d+):(-?\d+):(\d)$/
      g_id, t_id, s_all = $1.to_i, $2.to_i, $3.to_i

      # 1. Aggiorna il target nel database
      Context.set_private_context(user_id, g_id, t_id)
      context.reload!
      # 2. Popup di conferma
      nomi = DataManager.recupera_nomi_contesto(g_id, t_id)
      etichetta = (nomi[:nome] == "Privata") ? nomi[:topic] : "#{nomi[:nome]} #{nomi[:topic]}".strip
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🎯 Target: #{etichetta}")

      KeyboardGenerator.show_private_keyboard(bot, context.chat_id, context) if context.private_chat?
      # Non chiamare la tastiera fisica qui! Altrimenti sovrascrive il menu gruppi.

      # 4. Refresh solo del contenuto del messaggio (i pallini 🎯/📂)
      MessageHandler.handle_myitems(
        bot,
        callback.message.chat.id,
        user_id,
        callback,
        0,
        (s_all == 1)
      )
    when /^mycomprato:(\d+):(-?\d+):(\d+):(\d+):(\d)$/
      bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil

      item_id, g_id, t_id, page, s_all = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i

      # 1. Logica DB (La tua)
      if DataManager.comprato?(item_id)
        DataManager.despunta_articolo(item_id)
      else
        DataManager.spunta_articolo(item_id, user_id)
      end

      # 2. Refresh Standard
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      header = DataManager.genera_header_contesto(g_id, t_id)

      options = {
        nome_target: header,
        is_group: !context.private_chat?,
      }

      # Passiamo l'hash invece della stringa
      ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, options)

      # 3. Edit (Il tuo blocco begin/rescue)
      self.edit_veloce(bot, context, callback, ui)

      # --- RAMO 2: LISTA "TUTTI GLI ARTICOLI" (Refresh Differenziato) ---
    when /^myallcomprato:(\d+):(-?\d+):(\d+):(\d+):(\d)$/
      bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil

      item_id, g_id, t_id, page, s_all = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i

      # 1. Logica DB (IDENTICA - DRY)
      if DataManager.comprato?(item_id)
        DataManager.despunta_articolo(item_id)
      else
        DataManager.spunta_articolo(item_id, user_id)
      end

      # 2. Refresh GLOBALE (Cambia solo questo!)
      items = DataManager.prendi_articoli_per_storico(g_id, t_id, user_id, s_all == 1)
      MessageHandler.handle_myitems(bot, context.chat_id, user_id, callback, page, s_all == 1)
      # 3. Edit
      # self.edit_veloce(bot, context, callback, ui)

      # --------------------------------------------------------------------------
      # LA SCOPETTA (Svuota carrello -> Storico)
      # --------------------------------------------------------------------------
    when /^superscopetta:(\d)$/
      puts "DEBUG: Entrato in Superscopetta"
      is_all = ($1.to_i == 1)
      u_name = callback.from.first_name

      # 1. RISPOSTA IMMEDIATA (Sblocca l'interfaccia ed evita il timeout 400)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🧹 Pulizia in corso...") rescue nil

      articoli = DataManager.articoli_da_superscopetta(user_id, is_all)
      puts "DEBUG: Articoli trovati: #{articoli.size}"

      if articoli.any?
        mappa = articoli.group_by { |a| [a["gruppo_id"], a["topic_id"]] }
        totale = 0

        mappa.each do |(g_id, t_id), items|
          ids = items.map { |i| i["id"] }
          rimossi = DataManager.esegui_scopetta(g_id, t_id, ids)
          totale += rimossi

          if rimossi > 0 && g_id != 0
            chat_id_dest = DataManager.get_real_chat_id(g_id)
            articoli_attuali = DataManager.prendi_articoli_per_storico(g_id, t_id, user_id, is_all)

            # Conta articoli con colonna 'comprato' vuota (ancora da prendere)
            articoli_rimasti = articoli_attuali.count { |a| a["comprato"].to_s.strip.empty? }

            msg = if articoli_rimasti == 0
                "🛒 <b>#{u_name}</b> ha terminato la spesa."
              else
                "🛒 <b>#{u_name}</b> ha terminato la spesa, controlla gli articoli rimasti."
              end

            bot.api.send_message(
              chat_id: chat_id_dest,
              message_thread_id: (t_id != 0 ? t_id : nil),
              text: msg,
              parse_mode: "HTML",
            ) rescue nil
          end
        end
        # NOTA: Abbiamo rimosso il secondo answer_callback_query qui
      end

      # REFRESH UI
      puts "DEBUG: Lancio Refresh post-scopetta..."
      target_chat_id = chat_id || callback.message.chat.id
      MessageHandler.handle_myitems(bot, target_chat_id, user_id, callback, 0, is_all)
    when /^ui_cleanup:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🧹 Lista pulita!")

      # 1. Eseguiamo la pulizia
      DataManager.esegui_scopetta(g_id, t_id)

      # 2. Controllo articoli rimasti per il messaggio condizionale
      articoli_rimasti = DataManager.prendi_articoli_ordinati(g_id, t_id).size

      # 3. Notifica al gruppo (solo se l'utente opera dalla sua chat privata)
      if g_id != 0 && callback.message.chat.type == "private"
        target_chat = DataManager.get_real_chat_id(g_id)
        u_name = callback.from.first_name

        testo_notifica = if articoli_rimasti == 0
            "🛒 **#{u_name}** ha terminato la spesa."
          else
            "🛒 **#{u_name}** ha terminato la spesa, controlla gli articoli rimasti."
          end

        bot.api.send_message(
          chat_id: target_chat,
          text: testo_notifica,
          parse_mode: "Markdown",
          message_thread_id: (t_id != 0 ? t_id : nil),
        )
      end

      # Torna sempre a pagina 0 dopo la pulizia
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)
    when /^pin_refresh:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🔄 Lista aggiornata")
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)

      # --------------------------------------------------------------------------
      # CAMBIO CONTESTO (Attivazione Gruppo da Privato)
      # --------------------------------------------------------------------------
    when /^set_private_group:(-?\d+):(\d+):(.+)$/
      g_id, t_id, t_name = $1.to_i, $2.to_i, $3

      Context.set_private_context(user_id, g_id, t_id, t_name)

      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🎯 Target impostato: #{t_name}")

      # Notifica di avvenuta attivazione
      bot.api.edit_message_text(
        chat_id: context.chat_id,
        message_id: callback.message.message_id,
        text: "✅ **Modalità Privata Attiva**\nOra i comandi `+` e `?` puntano a:\n📦 #{t_name}",
        parse_mode: "Markdown",
      )
    when /^ui_back_to_list:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      # Confermiamo subito il click per evitare il timeout di Telegram
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "Aggiornamento in corso...")

      # Eseguiamo il refresh sulla pagina 0
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)
    when /^show_photos:(\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      c_id = callback.message.chat.id

      # DEFINIZIONE DELLA VARIABILE (Il pezzo mancante!)
      # Se la chat è privata (>0), il thread_id deve essere nil
      actual_thread_id = (c_id > 0) ? nil : t_id

      articoli = DataManager.prendi_articoli_ordinati(g_id, t_id).select { |i| i["ha_foto"].to_i > 0 }

      if articoli.empty?
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Nessuna 📸 in questa lista.")
      else
        bot.api.answer_callback_query(callback_query_id: callback.id)

        articoli.each do |art|
          foto_ids = DataManager.prendi_foto_articolo(art["id"])
          foto_ids.each do |f|
            begin
              bot.api.send_photo(
                chat_id: c_id,
                photo: f["file_id"],
                caption: "📸 Articolo: <b>#{art["nome"]}</b>",
                parse_mode: "HTML",
                message_thread_id: actual_thread_id, # Ora la variabile esiste!
                reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(
                  inline_keyboard: [[
                    # Usiamo il tuo ui_close che è già perfetto e DRY
                    Telegram::Bot::Types::InlineKeyboardButton.new(text: "🗑️ Chiudi", callback_data: "ui_close"),
                  ]],
                ),
              )
            rescue => e
              puts "❌ Errore API durante invio foto: #{e.message}"
            end
          end
        end
      end

      # --------------------------------------------------------------------------
      # APERTURA CHECKLIST (Suggerimenti dallo Storico)
      # --------------------------------------------------------------------------
    when /^ui_checklist:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i

      # 1. Generiamo il markup
      markup = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)

      if markup
        # 2a. Risposta "vuota" (toglie solo l'orologino)
        bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil

        bot.api.edit_message_text(
          chat_id: context.chat_id,
          message_id: callback.message.message_id,
          text: "📋 **Suggerimenti dall'ultimo acquisto**\nClicca per aggiungere alla lista attuale:",
          reply_markup: markup,
          parse_mode: "Markdown",
        )
      else
        # 2b. Risposta con testo (mostra il bannerino "Storico vuoto")
        # Questa è l'UNICA risposta inviata in questo ramo
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Storico ancora vuoto!") rescue nil
      end

      # --------------------------------------------------------------------------
      # AGGIUNTA RAPIDA DALLO STORICO
      # --------------------------------------------------------------------------
      # In CallbackHandler
      # --- Nel CALLBACK_HANDLER ---
    when /^aggiungi:(\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      c_id = callback.message.chat.id
      user_name = callback.from.first_name

      DataManager.set_pending(
        chat_id: c_id,
        topic_id: t_id,
        action: "add:#{user_name}",
        gruppo_id: g_id,
      )

      # 1. Capiamo se siamo in privata o gruppo
      is_private = callback.message.chat.type == "private"
      thread_to_use = is_private ? nil : (t_id > 0 ? t_id : nil)

      # 2. Feedback visivo: diciamo all'utente DOVE sta aggiungendo
      info_target = DataManager.genera_header_contesto(g_id, t_id)

      bot.api.send_message(
        chat_id: c_id,
        message_thread_id: thread_to_use, # <--- IL PEZZO MANCANTE!
        text: "📝 <b>#{user_name}</b>, sessione aperta per:\n#{info_target}\n\nScrivi i prodotti o invia una foto.",
        parse_mode: "HTML",
      )

      #bot.api.answer_callback_query(callback_query_id: callback.id)
when /^add_from_hist:(.+):(-?\d+):(\d+)$/
  nome, g_id, t_id = $1, $2.to_i, $3.to_i
  bot.api.answer_callback_query(callback_query_id: callback.id) rescue nil

  # Recupero nome utente (Uniforme a core_aggiunta)
  u_name = callback.from.first_name
  t_chat_id = DataManager.prendi_telegram_chat_id(g_id)

  esiste_id = DB.get_first_value(
    "SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND (comprato IS NULL OR comprato = '')",
    [g_id, t_id, nome.downcase]
  )

  if esiste_id
    DataManager.rimuovi_da_lista(esiste_id)
    
    # MESSAGGIO UNIFORMATO (Rimozione)
    if t_chat_id && t_chat_id != callback.message.chat.id
      bot.api.send_message(
        chat_id: t_chat_id,
        text: "➖ <b>#{u_name}</b> ha rimosso: #{nome}", # Stesso stile: Nome + Grassetto
        parse_mode: "HTML",
        message_thread_id: t_id != 0 ? t_id : nil
      )
    end
  else
    DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: user_id, items_text: nome, topic_id: t_id)
    
    # MESSAGGIO UNIFORMATO (Aggiunta)
    if t_chat_id && t_chat_id != callback.message.chat.id
      bot.api.send_message(
        chat_id: t_chat_id,
        text: "➕ <b>#{u_name}</b> ha aggiunto: #{nome}", # Icona ➕ come nel core_aggiunta
        parse_mode: "HTML",
        message_thread_id: t_id != 0 ? t_id : nil
      )
    end
  end

  # Refresh UI
  nuovo_markup = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)
  bot.api.edit_message_reply_markup(chat_id: callback.message.chat.id, message_id: callback.message.message_id, reply_markup: nuovo_markup)
   
      when /^delete_item:(\d+):(-?\d+):(\d+):(\d+)$/
      item_id, g_id, t_id, page = $1.to_i, $2.to_i, $3.to_i, $4.to_i

      nome_art = DataManager.get_nome_articolo(item_id)
      DataManager.rimuovi_item_diretto(item_id)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🗑️ Rimosso")

      # NOTIFICA: Solo se l'azione parte dalla chat privata
      is_in_private = callback.message.chat.type == "private"

      if g_id != 0 && is_in_private
        target_chat = DataManager.get_real_chat_id(g_id)
        begin
          bot.api.send_message(
            chat_id: target_chat,
            text: "❌ <b>#{callback.from.first_name}</b> ha cancellato: #{nome_art}",
            parse_mode: "html",
            message_thread_id: (t_id != 0 ? t_id : nil),
          )
        rescue => e
          puts "⚠️ [NOTIFICA_SKIP] #{e.message}"
        end
      end

      # Refresh dell'interfaccia
      self.refresh_ui(bot, callback, context, g_id, t_id, page, 0)
    when /^set_target:(.+):(.+)$/
      g_db_id = $1.to_i # L'ID interno (es: 50)
      t_id = $2.to_i    # L'ID del topic (es: 2)
      u_id = callback.from.id

      # 1. Salviamo il target nel JSON tramite DataManager
      # (Manteniamo la logica di salvataggio separata)
      conf = DataManager.carica_config_utente(u_id) || {}
      conf["target_g"] = g_db_id
      conf["target_t"] = t_id
      DataManager.salva_config_utente(u_id, conf)

      # 2. CHIAMATA PULITA: Il DataManager risolve tutto.
      # Passiamo g_db_id (50). Sarà lui a fare la query internamente per trovare il nome "sperimentale"
      nome_t = DataManager.get_topic_name(g_db_id, t_id)

      # 3. Feedback all'utente usando la stringa restituita
      # answer_callback_query mostra il bannerino in alto su Telegram
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🎯 Target: #{nome_t}")

      # send_message conferma l'operazione nella chat
      bot.api.send_message(
        chat_id: u_id,
        text: "✅ Destinazione impostata: *#{nome_t}*",
        parse_mode: "Markdown",
      )

      # --------------------------------------------------------------------------
      # CHIUSURA INTERFACCIA
      # --------------------------------------------------------------------------

    when /^myitems_page:(\d+):(\d+):(\d)$/
      u_id, target_page, s_all = $1.to_i, $2.to_i, ($3.to_i == 1)
      MessageHandler.handle_myitems(bot, callback.message.chat.id, u_id, callback, target_page, s_all)
      bot.api.answer_callback_query(callback_query_id: callback.id)

      # In callback_handler.rb all'interno del metodo self.route

      # VERSIONE UNIFICATA E DEFINITIVA
    when "ui_close", "close_barcode", /^ui_close:/, /^carte_chiudi/, /^checklist_close/
      puts "[CALLBACK] 🗑️ Chiusura interfaccia richiesta (Data: #{data})"

      begin
        target_chat_id = callback.message.chat.id
        target_msg_id = callback.message.message_id
        bot.api.delete_message(chat_id: target_chat_id, message_id: target_msg_id)
      rescue Telegram::Bot::Exceptions::ResponseError => e
        # Se l'errore è "not found", ignoriamo (il messaggio è già sparito)
        unless e.message.include?("message to delete not found")
          puts "⚠️ [CALLBACK] Errore eliminazione: #{e.message}"
          # Prova a togliere i bottoni se non può cancellare (messaggio vecchio)
          begin
            bot.api.edit_message_reply_markup(chat_id: target_chat_id, message_id: target_msg_id, reply_markup: nil)
          rescue => e_markup
            # Silenzioso anche qui se il messaggio è sparito nel frattempo
          end
        end
      end
      bot.api.answer_callback_query(callback_query_id: callback.id)

      # --- NUOVA GESTIONE CAMBIO GRUPPO DA PRIVATA ---
    when /^private_set:(\d+):(\d+):(\d+)$/
      g_id, u_id, t_id = $1.to_i, $2.to_i, $3.to_i

      # 1. Recuperiamo il nome del topic per la configurazione
      t_name = DataManager.get_topic_name(g_id, t_id)

      # 2. Salviamo la configurazione tramite DataManager
      nuova_conf = {
        "db_id" => g_id,
        "topic_id" => t_id,
        "topic_name" => t_name,
      }
      DataManager.salva_config_utente(u_id, nuova_conf)

      puts "[CALLBACK] 🎯 Context Privato impostato: G:#{g_id} T:#{t_id} (#{t_name})"

      # 3. Feedback all'utente e AGGIORNAMENTO tastiera (per il ✅)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🎯 Target: #{t_name}")
      KeyboardGenerator.show_group_selector(bot, u_id, callback.message.message_id)
      # --- AGGIUNTA FONDAMENTALE PER AGGIORNARE I TASTONI ---
      # 4. Creiamo un contesto aggiornato e rimandiamo la tastiera fisica
      new_context = Context.new(chat_id: callback.message.chat.id, user_id: u_id, scope: :private)
      KeyboardGenerator.show_private_keyboard(bot, callback.message.chat.id, new_context)
    else
      puts "[CALLBACK] ❓ Azione non gestita: #{data}"
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "Funzione in fase di refactoring")
    end
  end

  # ==============================================================================
  # METODI DI SUPPORTO UI
  # ==============================================================================

  # handlers/callback_handler.rb

  # handlers/callback_handler.rb

  # In handlers/callback_handler.rb
  def self.refresh_ui(bot, callback, context, g_id, t_id, page, s_all)
    items = DataManager.prendi_articoli_ordinati(g_id, t_id)
    header = DataManager.genera_header_contesto(g_id, t_id)

    # Determiniamo se siamo in chat privata o gruppo per le opzioni
    is_private = callback.message.chat.type == "private"
    options = { nome_target: header, is_group: !is_private, page: page.to_i }

    # Qui sta il trucco: genera_lista restituisce un HASH
    result = KeyboardGenerator.genera_lista(items, g_id, t_id, page, options)

    # Estraiamo il markup dall'hash
    ui = result[:markup]

    # LOG DI CONTROLLO
    puts "📟 [UI_REFRESH] Articoli: #{items.size} | Righe tastiera: #{ui.inline_keyboard.size}"

    c_id = callback.message.chat.id
    m_id = callback.message.message_id

    self.edit_veloce(bot, c_id, m_id, ui)
  end

  def self.edit_veloce(bot, chat_id, message_id, markup)
    # Se chat_id è un oggetto Context o Chat, estraiamo l'id numerico
    final_c_id = chat_id.respond_to?(:chat_id) ? chat_id.chat_id : chat_id
    final_c_id = final_c_id.id if final_c_id.respond_to?(:id)

    # Se message_id è un oggetto CallbackQuery o Message, estraiamo l'id numerico
    final_m_id = if message_id.respond_to?(:message)
        message_id.message.message_id
      elsif message_id.respond_to?(:message_id)
        message_id.message_id
      else
        message_id
      end

    # Se markup è ancora l'intero Hash del generatore, estraiamo solo il markup
    final_markup = markup.is_a?(Hash) ? markup[:markup] : markup

    puts "📡 [API_EDIT] Chat:#{final_c_id} | Msg:#{final_m_id}"

    bot.api.edit_message_reply_markup(
      chat_id: final_c_id.to_i,
      message_id: final_m_id.to_i,
      reply_markup: final_markup,
    )
  rescue Telegram::Bot::Exceptions::ResponseError => e
    if e.message.include?("message is not modified")
      puts "ℹ️ [API_INFO] Refresh ignorato: contenuto identico."
    else
      puts "❌ [API_ERR] #{e.message}"
    end
  end

  def self.handle_approve_user(bot, callback_query, chat_id, target_user_id, username, full_name)
    # ✅ Azione su DB centralizzata in Whitelist
    Whitelist.approve_user(target_user_id, username, full_name.gsub("_", " "))

    # Conferma al creatore (chi ha cliccato il tasto)
    bot.api.send_message(
      chat_id: chat_id,
      text: "✅ Utente #{full_name} (@#{username}) approvato e aggiunto alla whitelist.",
    )

    # Notifica all'utente approvato
    bot.api.send_message(
      chat_id: target_user_id,
      text: "🎉 La tua richiesta di accesso è stata approvata! Ora puoi usare il bot.",
    )

    # Rimuoviamo i bottoni dal messaggio originale per evitare doppi click
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: callback_query.message.message_id,
      text: "✅ Richiesta approvata per #{full_name}",
    )
  end

  def self.handle_reject_user(bot, callback_query, chat_id, target_user_id)
    # ❌ Azione su DB centralizzata in Whitelist
    Whitelist.remove_pending_request(target_user_id)

    bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Richiesta rifiutata")

    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: callback_query.message.message_id,
      text: "❌ Richiesta rifiutata per ID: #{target_user_id}",
    )

    # Notifica all'utente rifiutato
    begin
      bot.api.send_message(
        chat_id: target_user_id,
        text: "🚫 La tua richiesta di accesso è stata rifiutata dall'amministratore.",
      )
    rescue => e
      puts "⚠️ Impossibile notificare utente rifiutato: #{e.message}"
    end
  end
end
