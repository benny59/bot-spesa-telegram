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

    when /^carte:/, "close_barcode"
      CarteFedelta.handle_callback(bot, callback)
    when /^carte_confirm_delete:(\d+)$/
      CarteFedelta.delete_card(bot, context.user_id, $1.to_i)
    when "carte_cancel_delete"
      bot.api.delete_message(chat_id: context.chat_id, message_id: callback.message.message_id)

      # --------------------------------------------------------------------------
      # GESTIONE CARRELLO (Soluzione B: Spunta/Despunta)
      # --------------------------------------------------------------------------
      # handlers/callback_handler.rb -> dentro il case update.data

      # --------------------------------------------------------------------------
      # GESTIONE PAGINAZIONE
      # --------------------------------------------------------------------------
      # In handlers/callback_handler.rb (dentro la gestione ui_page)
    when /^ui_page:(\d+):(\d+):(\d+)$/
      g_id, t_id, page = $1.to_i, $2.to_i, $3.to_i
      puts "[DEBUG] 📄 Cambio Pagina -> G:#{g_id} T:#{t_id} P:#{page}" # LOG 1

      # 1. Recupero dati e nome (usando il metodo che abbiamo stabilito)
      items = DataManager.prendi_articoli_ordinati(g_id, t_id)
      nome_t = DataManager.get_topic_name(g_id, t_id)
      puts "[DEBUG] 🏷️ Nome Topic per Header: #{nome_t}" # LOG 2

      # 2. Costruzione Header (uniforme a quello che volevi)
      g_nome = (g_id == 0) ? "Privata" : (DB.get_first_value("SELECT nome FROM gruppi WHERE id = ?", [g_id]) || "Gruppo")
      header = (g_id == 0) ? "Lista #{nome_t}" : "#{g_nome}: Lista #{nome_t}"

      # 3. Generazione UI
      ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

      # 4. SOSTITUZIONE del messaggio esistente
      begin
        bot.api.edit_message_text(
          chat_id: callback.message.chat.id,
          message_id: callback.message.message_id,
          text: ui[:text],
          reply_markup: ui[:markup],
          parse_mode: "Markdown",
        )
        puts "[DEBUG] ✅ Messaggio sostituito con successo"
      rescue => e
        puts "[DEBUG] ❌ Errore Edit: #{e.message}"
        # Fallback se l'edit fallisce
        bot.api.send_message(chat_id: callback.message.chat.id, text: ui[:text], reply_markup: ui[:markup], parse_mode: "Markdown")
      end

      bot.api.answer_callback_query(callback_query_id: callback.id)

      # --------------------------------------------------------------------------
      # GESTIONE RITORNO ALLA LISTA (Fix per il tasto Indietro)
      # --------------------------------------------------------------------------
    when /^ui_back_to_list:(-?\d+):(\d+)$/
      g_id, t_id = $1.to_i, $2.to_i
      bot.api.answer_callback_query(callback_query_id: callback.id)
      # Torna alla pagina 0 della lista principale
      self.refresh_ui(bot, callback, context, g_id, t_id, 0, 0)

      # Toggle "Comprato" (Mette nel carrello o toglie)
    when /^mycomprato:(\d+):(-?\d+):(\d+):(\d+):(\d)$/
      item_id, g_id, t_id, page, s_all = $1.to_i, $2.to_i, $3.to_i, $4.to_i, $5.to_i

      # Verifichiamo lo stato attuale per decidere se spuntare o despuntare
      item = DB.get_first_row("SELECT comprato FROM items WHERE id = ?", [item_id])

      if item && (item["comprato"].nil? || item["comprato"].empty?)
        DataManager.spunta_articolo(item_id, user_name)
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "🛒 Messo nel carrello")
      else
        DataManager.despunta_articolo(item_id)
        bot.api.answer_callback_query(callback_query_id: callback.id, text: "🔄 Riportato in lista")
      end

      # Rinfresco della UI (Metodo da implementare nel MessageHandler o UI Manager)
      self.refresh_ui(bot, callback, context, g_id, t_id, page, s_all)

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
    when /^ui_close:(-?\d+):(\d+)$/
      begin
        bot.api.delete_message(chat_id: context.chat_id, message_id: callback.message.message_id)
      rescue => e
        puts "[CALLBACK] ⚠️ Errore chiusura UI: #{e.message}"
      end
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

  def self.refresh_ui(bot, callback, context, g_id, t_id, page, s_all)
    puts "[REFRESH] 🔄 Avvio refresh: G:#{g_id} T:#{t_id} P:#{page}" # LOG 1

    # 1. Recupero nome e dati
    nome_topic = DataManager.get_topic_name(g_id, t_id)
    puts "[REFRESH] 🏷️ Nome recuperato: '#{nome_topic}'" # LOG 2

    items = DataManager.prendi_articoli_ordinati(g_id, t_id)

    # 2. Costruzione Header
    g_nome = (g_id == 0) ? "Privata" : (DB.get_first_value("SELECT nome FROM gruppi WHERE id = ?", [g_id]) || "Gruppo")
    header = (g_id == 0) ? "Lista #{nome_topic}" : "#{g_nome}: Lista #{nome_topic}"

    # 3. Generazione UI
    ui = KeyboardGenerator.genera_lista(items, g_id, t_id, page, header)

    # 4. Tentativo di EDIT
    begin
      puts "[REFRESH] 📤 Invio edit_message_text al msg_id: #{callback.message.message_id}" # LOG 3
      bot.api.edit_message_text(
        chat_id: callback.message.chat.id,
        message_id: callback.message.message_id,
        text: ui[:text],
        reply_markup: ui[:markup],
        parse_mode: "Markdown",
      )
      puts "[REFRESH] ✅ Edit completato con successo" # LOG 4
    rescue Telegram::Bot::Exceptions::ResponseError => e
      if e.message.include?("message is not modified")
        puts "[REFRESH] ℹ️ Nessuna modifica necessaria (stesso contenuto)"
      else
        puts "[REFRESH] ❌ ERRORE TELEGRAM: #{e.message}"
        # Se l'edit fallisce, proviamo a rimandarlo per non lasciare l'utente a piedi
        bot.api.send_message(chat_id: callback.message.chat.id, text: ui[:text], reply_markup: ui[:markup], parse_mode: "Markdown")
      end
    rescue => e
      puts "[REFRESH] 💥 ERRORE GENERICO: #{e.message}\n#{e.backtrace.first}"
    end
  end
end
