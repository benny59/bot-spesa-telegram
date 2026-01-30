# handlers/callback_handler.rb
require_relative "storico_manager"
require_relative "../models/carte_fedelta"

require_relative "../models/context"
require_relative "../db"

class CallbackHandler
  def self.route(bot, callback, context)
    data = callback.data
    user_id = callback.from.id
    user_name = callback.from.first_name

    puts "[CALLBACK] 🖱️ Ricevuto: '#{data}' da #{user_name}"

    case data
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
      
      # 1. Recupero sicuro del Topic
      t_id = (callback.message.respond_to?(:message_thread_id) ? callback.message.message_thread_id : 0).to_i
      
      # 2. RECUPERO SICURO del g_id (Evitiamo NoMethodError per nil)
      # Se context.config è nil, usiamo DataManager per recuperare il g_id dal chat_id del messaggio
      g_id = 0
      if context && context.config
        g_id = context.config["db_id"].to_i
      else
        # Fallback: recuperiamo il gruppo partendo dall'ID della chat di Telegram
        gruppo = DataManager.prendi_gruppo_da_chat_id(callback.message.chat.id)
        g_id = gruppo ? gruppo["id"].to_i : 0
      end

      puts "[DEBUG-CARTE] 👤 Erasma/User ID: #{callback.from.id} | Carta ID: #{card_id}"
      puts "[DEBUG-CARTE] 📍 Info: Gruppo DB: #{g_id} | Chat TG: #{callback.message.chat.id} | Topic: #{t_id}"

      # 3. Chiamata con controllo
      begin
        CarteFedeltaGruppo.mostra_carta_gruppo(bot, callback.message.chat.id, g_id, card_id, t_id)
        bot.api.answer_callback_query(callback_query_id: callback.id)
        puts "✅ [DEBUG-CARTE] Visualizzazione inviata con successo"
      rescue => e
        puts "❌ [RUNTIME ERROR CARTE] #{e.message}"
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "⚠️ Errore caricamento carta")
      end
      
           # 2. Chiusura tastiera carte
    when "close_barcode"
      bot.api.answer_callback_query(callback_query_id: callback.id)
      bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id) rescue nil


      # FIX: Aggiunto alias per la chiusura specifica delle carte se usata
    when /^carte_chiudi:(-?\d+):(\d+)$/
      bot.api.answer_callback_query(callback_query_id: callback.id)
      bot.api.delete_message(chat_id: callback.message.chat.id, message_id: callback.message.message_id) rescue nil
    when /^carte_confirm_delete:(\d+)$/
      CarteFedelta.delete_card(bot, context.user_id, $1.to_i)
    when "carte_cancel_delete"
      bot.api.delete_message(chat_id: context.chat_id, message_id: callback.message.message_id)
      # Nel blocco 'when' che gestisce i callback
    when /^ui_cards:(\d+):(\d+)$/
      g_id = $1.to_i
      t_id = $2.to_i

      # Chiamiamo il metodo che ora userà DataManager.carte_disponibili_nel_gruppo(g_id)
      # Passiamo g_id esplicito per non farlo cercare a caso nel context
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

when /^trigger_list:(-?\d+):(\d+)$/
  g_id, t_id = $1.to_i, $2.to_i
  items = DataManager.prendi_per_contesto(g_id, t_id) #
  header = DataManager.genera_header_contesto(g_id, t_id) #
  ui = KeyboardGenerator.genera_lista(items, g_id, t_id, 0, header)
  
  bot.api.send_message(
    chat_id: callback.message.chat.id,
    message_thread_id: (t_id > 0 ? t_id : nil),
    text: ui[:text],
    reply_markup: ui[:markup],
    parse_mode: "HTML"
  )
  bot.api.answer_callback_query(callback_query_id: callback.id)
  
        
      
    when /^ui_back_to_list:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id)
      # Torna alla pagina 0 della lista principale
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)

      # Toggle "Comprato" (Mette nel carrello o toglie)
      # Esempio di gestione del click (Callback)
when /^mycomprato:(\d+):(-?\d+):(\d+):(\d+):(\d)$/
  item_id, g_id, t_id, page, s_all = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i
  
  # Usa gli oggetti corretti estratti dal callback
  c_id = callback.message.chat.id
  m_id = callback.message.message_id

  DataManager.spunta_articolo(item_id, user_id) # Spunta con ID utente per le iniziali
  
  # Refresh con i dati corretti
  items = DataManager.prendi_per_contesto(g_id, t_id)
  header = DataManager.genera_header_contesto(g_id, t_id)
  ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

  bot.api.edit_message_text(
    chat_id: c_id,
    message_id: m_id,
    text: ui[:text],
    reply_markup: ui[:markup],
    parse_mode: "HTML"
  )
      # --------------------------------------------------------------------------
      # LA SCOPETTA (Svuota carrello -> Storico)
      # --------------------------------------------------------------------------
      # callback_handler.rb
    when /^ui_cleanup:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      DataManager.esegui_scopetta(g_id, t_id)
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🧹 Lista pulita!")
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
      # Confermiamo il click e torniamo alla lista principale
      bot.api.answer_callback_query(callback_query_id: callback.id)
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)

      # --------------------------------------------------------------------------
      # APERTURA CHECKLIST (Suggerimenti dallo Storico)
      # --------------------------------------------------------------------------
    when /^ui_checklist:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i

      # Generiamo la tastiera dei suggerimenti dallo StoricoManager
      markup = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)

      if markup
        bot.api.edit_message_text(
          chat_id: context.chat_id,
          message_id: callback.message.message_id,
          text: "📋 **Suggerimenti dall'ultimo acquisto**\nClicca per aggiungere alla lista attuale:",
          reply_markup: markup,
          parse_mode: "Markdown",
        )
      else
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Storico ancora vuoto!")
      end

      # --------------------------------------------------------------------------
      # AGGIUNTA RAPIDA DALLO STORICO
      # --------------------------------------------------------------------------
    when /^add_from_hist:(.+):(-?\d+):(\d+)$/
      nome, g_id, t_id = $1, $2.to_i, $3.to_i

      # Controllo se esiste già
      esiste = DB.get_first_value(
        "SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND (comprato IS NULL OR comprato = '')",
        [g_id, t_id, nome.downcase]
      )

      if esiste
        # Se esiste, lo rimuoviamo (Deselezione)
        DB.execute("DELETE FROM items WHERE id = ?", [esiste])
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Rimosso: #{nome}")
      else
        # Se non esiste, lo aggiungiamo
        DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: context.user_id, items_text: nome, topic_id: t_id)
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Aggiunto: #{nome}")
      end

      # Refresh immediato della tastiera checklist per cambiare l'icona (+ / ✅)
      nuovo_markup = StoricoManager.genera_tastiera_checklist(bot, context, g_id, t_id)
      bot.api.edit_message_reply_markup(
        chat_id: callback.message.chat.id,
        message_id: callback.message.message_id,
        reply_markup: nuovo_markup,
      )
    when /^delete_item:(\d+):(-?\d+):(\d+):(\d+)$/
      item_id, g_id, t_id, page = $1.to_i, $2.to_i, $3.to_i, $4.to_i

      # Chiamata pulita al DataManager
      DataManager.rimuovi_item_diretto(item_id)

      bot.api.answer_callback_query(callback_query_id: callback.id, text: "🗑️ Rimosso")

      # Recupero nome topic per l'intestazione corretta
      nome_display = (g_id == 0) ? "Lista Personale" : DataManager.get_topic_name(callback.message.chat.id, t_id)

      # Refresh
      self.refresh_ui(bot, callback, context, g_id, t_id, page, 0)

      # In handlers/callback_handler.rb (aggiungere al case data)

      # handlers/callback_handler.rb (intorno alla riga 176)

      # handlers/callback_handler.rb

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
    target_msg_id  = callback.message.message_id

    bot.api.delete_message(chat_id: target_chat_id, message_id: target_msg_id)
  rescue => e
    puts "⚠️ [CALLBACK] Errore eliminazione: #{e.message}"
    # Se il messaggio è troppo vecchio (>48h) o mancano permessi, togliamo solo i bottoni
    begin
      bot.api.edit_message_reply_markup(chat_id: target_chat_id, message_id: target_msg_id, reply_markup: nil)
    rescue => e_markup
      puts "❌ [CALLBACK] Impossibile anche modificare il markup: #{e_markup.message}"
    end
  end
  # Rispondiamo sempre alla query per togliere l'icona del caricamento dal bottone
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
    else
      puts "[CALLBACK] ❓ Azione non gestita: #{data}"
      bot.api.answer_callback_query(callback_query_id: callback.id, text: "Funzione in fase di refactoring")
    end
    bot.api.answer_callback_query(callback_query_id: callback.id)
  end

  # ==============================================================================
  # METODI DI SUPPORTO UI
  # ==============================================================================

  # handlers/callback_handler.rb

  # handlers/callback_handler.rb

# In handlers/callback_handler.rb
def self.refresh_ui(bot, callback, context, g_id, t_id, page, s_all)
  # Usa il metodo che ha i JOIN per le iniziali MB/ER
  items = DataManager.prendi_per_contesto(g_id, t_id)
  header = DataManager.genera_header_contesto(g_id, t_id) #

  ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

  bot.api.edit_message_text(
    chat_id: callback.message.chat.id,
    message_id: callback.message.message_id,
    text: ui[:text],
    reply_markup: ui[:markup],
    parse_mode: "HTML" # Risolve il problema estetico dei tag visibili
  )
rescue => e
  puts "[REFRESH ERROR] #{e.message}"
end
    
  end
