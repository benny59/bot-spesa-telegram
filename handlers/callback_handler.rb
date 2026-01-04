# handlers/callback_handler.rb
require_relative "../models/lista"
require_relative "../models/group_manager"
require_relative "../models/whitelist"
require_relative "../models/preferences"
require_relative "../models/carte_fedelta"
require_relative "../models/carte_fedelta_gruppo"
require_relative "../utils/keyboard_generator"
require_relative "../db"

class CallbackHandler
  def self.route(bot, callback, context)
    puts "->#{callback.data}"
    data = callback.data

    case data

    when /^show_storico:(\d+):(\d+)$/
      gruppo_id = $1.to_i
      topic_id = $2.to_i

      acquisti = StoricoManager.ultimi_acquisti(gruppo_id, topic_id)
      testo = StoricoManager.formatta_storico(acquisti)

      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Chiudi",
              callback_data: "ui_close:#{context.chat_id}:#{context.topic_id}",
            ),
          ],
        ],
      )

      bot.api.send_message(
        chat_id: context.chat_id,
        message_thread_id: context.topic_id,
        text: testo,
        parse_mode: "Markdown",
        reply_markup: keyboard,
      )

      bot.api.answer_callback_query(callback_query_id: callback.id)
    when /^comprato:(\d+):(\d+)(?::(\d+))?$/
      handle_comprato(bot, callback, context.chat_id, context.user_id, $1.to_i, $2.to_i, ($3 || context.topic_id).to_i || 0)
    when /^cancella:(\d+):(\d+)(?::(\d+))?$/
      handle_cancella(bot, callback, context.chat_id, context.user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^info:(\d+):(\d+)(?::(\d+))?$/
      handle_info(bot, callback, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^foto_menu:(\d+):(\d+)(?::(\d+))?$/
      handle_foto_menu(bot, callback, context.chat_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^(add_foto|replace_foto):(\d+):(\d+)(?::(\d+))?$/
      handle_add_replace_foto(bot, callback, context.chat_id, $2.to_i, $3.to_i, $4&.to_i || 0)
    when /^remove_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_remove_foto(bot, callback, context.chat_id, context.user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^toggle_view_mode:(\d+)(?::(\d+))?$/
      handle_toggle_view_mode(bot, callback, context.chat_id, context.user_id, $1.to_i, $2&.to_i || 0)
    when /^cancella_tutti:(\d+)(?::(\d+))?$/
      handle_cancella_tutti(bot, callback, context.chat_id, context.user_id, $1.to_i, $2&.to_i || 0)
    when /^mostra_carte:(\d+)(?::(\d+))?$/
      CarteFedeltaGruppo.show_group_cards(bot, $1.to_i, context.chat_id, context.user_id, context.topic_id)
    when /^aggiungi:(\d+)(?::(\d+))?$/
      handle_aggiungi(bot, callback, context.chat_id, $1.to_i, $2&.to_i || 0)
    when /^checklist_close:(-?\d+):(\d+)$/
      StoricoManager.gestisci_chiusura_checklist(bot, callback, data)
    when /^ui_close:(-?\d+):(\d+)$/
      gestisci_chiusura_ui(bot, callback, data)
    when "switch_to_group"
      begin
        user_id = context.user_id # o msg.from.id
        key = "context:#{user_id}"

        # ✅ RIMOZIONE RECORD DAL DB
        DB.execute("DELETE FROM config WHERE key = ?", [key])
        puts "🧹 [Config] Contesto rimosso dal DB per #{key}"

        # ✅ AGGIORNAMENTO ISTANTANEO TASTIERA
        # Il check ✅ si sposterà ora sul tasto "Modalità Gruppo"
        Context.show_group_selector(bot, user_id, callback.message.message_id)

        bot.api.answer_callback_query(callback_query_id: callback.id, text: "Modalità Gruppo ripristinata")
      rescue => e
        puts "❌ ERRORE SWITCH: #{e.message}"
      end
    when /^private_set:(-?\d+):(-?\d+):(\d+)$/
      # LOG DI ENTRATA
      puts "DEBUG CALLBACK: Ricevuta richiesta private_set"
      puts "DEBUG DATA: #{data}"

      db_id = $1.to_i
      chat_id = $2.to_i
      topic_id = $3.to_i

      puts "DEBUG PARSED: db_id=#{db_id}, chat_id=#{chat_id}, topic_id=#{topic_id}"

      begin
        # Recupera nome topic
        t_row = DB.get_first_row("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [chat_id, topic_id])
        t_name = t_row ? t_row["nome"] : (topic_id == 0 ? "Generale" : "Topic #{topic_id}")
        puts "DEBUG TOPIC NAME: #{t_name}"

        config_value = {
          db_id: db_id,
          chat_id: chat_id,
          topic_id: topic_id,
          topic_name: t_name,
        }.to_json

        # SALVATAGGIO
        key = "context:#{context.user_id}"
        DB.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, config_value])

        # ✅ AGGIORNAMENTO ISTANTANEO TASTIERA
        # Sposta il check sul gruppo appena cliccato
        Context.show_group_selector(bot, context.user_id, callback.message.message_id)

        bot.api.answer_callback_query(callback_query_id: callback.id, text: "✅ **Modalità privata attiva**Target: #{t_name}")

        #       bot.api.send_message(
        #         chat_id: context.user_id,
        #         text: "✅ **Modalità privata attiva**\nTarget: #{t_name}",
        #         parse_mode: "Markdown",
        #       )
      rescue => e
        puts "❌ ERRORE CALLBACK: #{e.message}"
        puts e.backtrace.first(3)
      end
    else
      # callback ignota → log silenzioso
    end
  end

  def self.handle(bot, msg)
    chat_id = msg.message.respond_to?(:chat) ? msg.message.chat.id : msg.from.id
    user_id = msg.from.id
    topic_id = msg.message.message_thread_id || 0
    puts "🧵 CALLBACK topic_id=#{topic_id}"

    data = msg.data.to_s
    puts "🖱 Callback: #{data} - User: #{user_id} - Chat: #{chat_id}"

    case data
    when "noop"
      handle_noop(bot, msg)
    when /^myitems_page:(\d+):(\d+)$/
      target_user_id = $1.to_i
      page = $2.to_i

      msg = callback_query = msg  # già passato come msg

      if target_user_id == user_id
        MessageHandler.handle_myitems(
          bot,
          msg.message.chat.id,
          user_id,
          msg.message,
          page
        )
      else
        bot.api.answer_callback_query(
          callback_query_id: msg.id,
          text: "❌ Non puoi cambiare pagina",
        )
      end
    when /^myitems_refresh:(\d+):(\d+)$/
      target_user_id = $1.to_i
      page = $2.to_i

      if target_user_id == user_id
        # ✅ RISPOSTA IMMEDIATA
        bot.api.answer_callback_query(
          callback_query_id: msg.id,
          text: "🔄 Aggiorno…",
          show_alert: false,
        )

        MessageHandler.handle_myitems(
          bot,
          msg.message.chat.id,
          user_id,
          msg.message,
          page
        )
      else
        bot.api.answer_callback_query(
          callback_query_id: msg.id,
          text: "❌ Non puoi aggiornare questa lista",
          show_alert: false,
        )
      end

      # 🔥 MODIFICA: Aggiungi topic_id opzionale a tutti i callback pattern
    when /^lista_page:(\d+):(\d+)(?::(\d+))?$/
      handle_lista_page(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^comprato:(\d+):(\d+)(?::(\d+))?$/
      handle_comprato(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^cancella:(\d+):(\d+)(?::(\d+))?$/
      handle_cancella(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^cancella_tutti:(\d+)(?::(\d+))?$/
      handle_cancella_tutti(bot, msg, chat_id, user_id, $1.to_i, $2&.to_i || 0)
    when /^azioni_menu:(\d+):(\d+)(?::(\d+))?$/
      handle_azioni_menu(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^cancel_azioni:(\d+):(\d+)(?::(\d+))?$/
      handle_cancel_azioni(bot, msg, chat_id)
    when /^view_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_view_foto(bot, msg, chat_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^mostra_carte:(\d+)(?::(\d+))?$/
      gruppo_id = $1.to_i
      CarteFedeltaGruppo.show_group_cards(bot, gruppo_id, chat_id, user_id, topic_id)
    when /^carte:(\d+):(\d+)$/
      CarteFedelta.handle_callback(bot, msg)
    when "carte_delete", /^carte_confirm_delete:(\d+)$/, "carte_back"
      CarteFedelta.handle_callback(bot, msg)
    when "close_barcode"
      begin
        # Prova a cancellare il messaggio
        bot.api.delete_message(chat_id: msg.message.chat.id, message_id: msg.message.message_id)
      rescue Telegram::Bot::Exceptions::ResponseError => e
        if e.message.include?("message to delete not found") || e.message.include?("message to edit not found")
          # Se non può cancellare (es. in gruppi), rispondi con un messaggio temporaneo
          bot.api.answer_callback_query(
            callback_query_id: msg.id,
            text: "✅ Chiuso",
            show_alert: false,
          )
        else
          # Per altri errori, prova a modificare il messaggio
          begin
            bot.api.edit_message_text(
              chat_id: msg.message.chat.id,
              message_id: msg.message.message_id,
              text: "✅ Schermata chiusa.",
            )
          rescue Telegram::Bot::Exceptions::ResponseError
            # Se anche la modifica fallisce, rispondi semplicemente alla callback
            bot.api.answer_callback_query(
              callback_query_id: msg.id,
              text: "✅ Chiuso",
            )
          end
        end
      end
    when "carte_cancel_delete"
      # Cancella il messaggio con la tastiera
      begin
        bot.api.delete_message(chat_id: msg.from.id, message_id: msg.message.message_id)
      rescue Telegram::Bot::Exceptions::ResponseError
        # Se non può cancellare, modifica il messaggio
        bot.api.edit_message_text(
          chat_id: msg.from.id,
          message_id: msg.message.message_id,
          text: "❌ Operazione annullata.",
        )
      end
      # 🔥 AGGIUNTA COMPLETA: Tutte le callback per le carte gruppo
    when /^carte_gruppo_delete:(\d+):(\d+)$/,
         /^carte_gruppo_confirm_delete:(\d+):(\d+)$/,
         /^carte_gruppo_back:(\d+)$/,
         /^carte_gruppo_add:(\d+):(\d+)$/,
         /^carte_gruppo_remove:(\d+):(\d+)$/,
         /^carte_gruppo_add_finish:(\d+)$/,
         /^carte_chiudi:(-?\d+):(\d+)$/
      CarteFedeltaGruppo.handle_callback(bot, msg)
    when /^carte_gruppo:(\d+):(\d+)(?::(\d+))?$/
      gruppo_id, carta_id = $1.to_i, $2.to_i
      topic_id = $3&.to_i || 0  # 🔥 Estrai topic_id
      CarteFedeltaGruppo.handle_callback(bot, msg)  # Questo passa alla classe corretta
    when /^checklist_toggle:[^:]+:\d+:\d+$/
    when /^checklist_toggle:[^:]+:\d+:\d+:\d+$/
      handled = StoricoManager.gestisci_toggle_checklist(bot, msg, data)
      bot.api.answer_callback_query(callback_query_id: msg.id) unless handled
    when /^checklist_confirm:\d+:\d+:\d+$/
      handled = StoricoManager.gestisci_conferma_checklist(bot, msg, data)
      bot.api.answer_callback_query(callback_query_id: msg.id) unless handled
    when /^checklist_add:[^:]+:\d+:\d+$/ # Delegato a StoricoManager
      handled = StoricoManager.gestisci_click_checklist(bot, msg, data)
      unless handled
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Errore nell'aggiunta")
      end
    when /^show_checklist:(\d+):(\d+)$/
      gruppo_id = $1.to_i
      topic_id = $2.to_i
      handle_show_checklist(bot, msg, chat_id, user_id, gruppo_id, topic_id)
    when /^checklist_close:(-?\d+):(\d+)$/
      StoricoManager.gestisci_chiusura_checklist(bot, msg, data)
    when /^approve_user:(\d+):([^:]*):(.+)$/
      handle_approve_user(bot, msg, chat_id, $1.to_i, $2, $3)
    when /^reject_user:(\d+)$/
      handle_reject_user(bot, msg, chat_id, $1.to_i)
    when /^show_list:(\d+)(?::(\d+))?$/
      handle_show_list(bot, msg, chat_id, user_id, $1.to_i, $2&.to_i || 0)
      # 🔥 MODIFICA: Aggiungi topic_id opzionale

    when /^show_storico:(\d+):(\d+)$/
      gruppo_id = $1.to_i
      topic_id = $2.to_i

      acquisti = StoricoManager.ultimi_acquisti(gruppo_id, topic_id)
      testo = StoricoManager.formatta_storico(acquisti)

      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [
            Telegram::Bot::Types::InlineKeyboardButton.new(
              text: "❌ Chiudi",
              callback_data: "ui_close:#{chat_id}:#{topic_id}",
            ),
          ],
        ],
      )

      bot.api.send_message(
        chat_id: msg.message.chat.id,
        message_thread_id: topic_id,
        text: testo,
        parse_mode: "Markdown",
        reply_markup: keyboard,
      )

      bot.api.answer_callback_query(callback_query_id: msg.id)
    when /^ui_close:(-?\d+):(\d+)$/
      gestisci_chiusura_ui(bot, msg, data)
    when /^(add_foto|replace_foto):(\d+):(\d+)(?::(\d+))?$/
      handle_add_replace_foto(bot, msg, chat_id, $2.to_i, $3.to_i, $4&.to_i || 0)
    when /^remove_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_remove_foto(bot, msg, chat_id, user_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^foto_menu:(\d+):(\d+)(?::(\d+))?$/
      handle_foto_menu(bot, msg, chat_id, $1.to_i, $2.to_i, $3&.to_i || 0)
    when /^toggle:(\d+):(\d+)(?::(\d+))?$/
      handle_toggle(bot, msg, $1.to_i, $2.to_i, $3&.to_i || 0)
      # 🔥 MODIFICA: Aggiungi topic_id opzionale
    when /^toggle_view_mode:(\d+)(?::(\d+))?$/
      handle_toggle_view_mode(bot, msg, chat_id, user_id, $1.to_i, $2&.to_i || 0)
      # 🔥 MODIFICA: Aggiungi topic_id opzionale
    when /^aggiungi:(\d+)(?::(\d+))?$/
      handle_aggiungi(bot, msg, chat_id, $1.to_i, $2&.to_i || 0)
    when /^cancel_foto:(\d+):(\d+)(?::(\d+))?$/
      handle_cancel_foto(bot, msg, chat_id)
    when /^info:(\d+):(\d+)(?::(\d+))?$/
      handle_info(bot, msg, $1.to_i, $2.to_i, $3&.to_i || 0)
    else
      puts "❌ Callback non riconosciuto: #{data}"
    end
  end

  private

  # 🔥 MODIFICA: Aggiungi topic_id ai metodi principali
  def self.handle_comprato(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    # Recuperiamo il nome dell'item prima del toggle per la notifica
    item_nome = DB.get_first_value("SELECT nome FROM items WHERE id = ?", [item_id])
    user_name = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || "Qualcuno"

    # Eseguiamo l'azione
    nuovo_stato = Lista.toggle_comprato(gruppo_id, item_id, user_id)

    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Stato aggiornato")

    # NOTIFICA
    emoji = (nuovo_stato.to_s.strip == "" || nuovo_stato.to_s == "0") ? "🔄" : "✅"
    azione = emoji == "✅" ? "ha preso" : "ha rimesso in lista"
    Context.notifica_gruppo_se_privato(bot, user_id, "#{emoji} *#{user_name}* #{azione}: #{item_nome}")

    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_cancella(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    item_nome = DB.get_first_value("SELECT nome FROM items WHERE id = ?", [item_id])
    user_name = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || "Qualcuno"

    Lista.cancella(gruppo_id, item_id, user_id)

    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Eliminato")

    # NOTIFICA
    Context.notifica_gruppo_se_privato(bot, user_id, "🗑️ *#{user_name}* ha rimosso: #{item_nome}")

    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_cancella_tutti(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    u_row = DB.get_first_row("SELECT first_name FROM user_names WHERE user_id = ?", [user_id])
    user_display = u_row ? u_row["first_name"] : "Utente #{user_id}"

    if Lista.cancella_tutti(gruppo_id, user_id)
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "✅ Articoli comprati rimossi")

      # NOTIFICA
      Context.notifica_gruppo_se_privato(bot, user_id, "🧹 *#{user_display}* ha rimosso tutti gli articoli completati.")

      KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
    else
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Solo admin può cancellare tutti")
    end
  end

  def self.handle_azioni_menu(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    has_image = Lista.ha_immagine?(item_id)
    item = Lista.trova(item_id)
    return unless item

    buttons = []
    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: item["comprato"] == 1 ? "❌ Segna da comprare" : "✅ Segna comprato",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "comprato:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    if has_image
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "👁️ Visualizza foto",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "view_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🔄 Sostituisci",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "replace_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🗑️ Rimuovi",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "remove_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
      ]
    else
      buttons << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📷 Aggiungi foto",
          # 🔥 MODIFICA: Aggiungi topic_id al callback_data
          callback_data: "add_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
        ),
      ]
    end

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "ℹ️ Informazioni",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "toggle:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Cancella articolo",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "cancella:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "↩️ Torna alla lista",
        # 🔥 MODIFICA: Aggiungi topic_id al callback_data
        callback_data: "cancel_azioni:#{item_id}:#{gruppo_id}:#{topic_id}",
      ),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)
    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "⚙️ *Menu azioni:* #{item["nome"]}",
      parse_mode: "Markdown",
      reply_markup: markup,
    )
  end

  def self.handle_noop(bot, msg)
    # Non fare nulla, ma rispondi per chiudere l'indicatore di caricamento
    bot.api.answer_callback_query(callback_query_id: msg.id)
  end

  def self.handle_lista_page(bot, msg, chat_id, user_id, gruppo_id, page, topic_id = 0)
    # Rispondi immediatamente alla callback
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "Caricamento pagina #{page + 1}...")

    # 🔥 MODIFICA: Passa topic_id
    success = KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, page, topic_id)

    # Se non è stato possibile aggiornare, rispondi comunque
    unless success
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "Nessun cambiamento necessario",
      )
    end
  end

  def self.handle_cancel_azioni(bot, msg, chat_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "↩️ Tornato alla lista")
    bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
  end

  def self.handle_view_foto(bot, msg, chat_id, item_id, gruppo_id, topic_id = 0)
    immagine = Lista.get_immagine(item_id)
    item = Lista.trova(item_id)

    if immagine && item && immagine["file_id"]
      caption = "📸 Foto associata all'articolo: \"#{item["nome"]}\""
      bot.api.send_photo(chat_id: chat_id, photo: immagine["file_id"], caption: caption)

      # RISPOSTA ALLA CALLBACK PER CHIUDERE L'INDICATORE DI CARICAMENTO
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "Foto visualizzata")
    else
      bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Nessuna foto trovata")
    end
  end

  def self.handle_approve_user(bot, msg, chat_id, user_id, username, full_name)
    # ✅ Aggiungi l'utente alla whitelist
    Whitelist.add_user(user_id, username, full_name.gsub("_", " "))
    Whitelist.remove_pending_request(user_id)

    # Conferma al creatore
    bot.api.send_message(
      chat_id: chat_id,
      text: "✅ Utente #{full_name} (@#{username}) approvato e aggiunto alla whitelist.",
    )

    # Notifica all'utente
    bot.api.send_message(
      chat_id: user_id,
      text: "🎉 La tua richiesta di accesso è stata approvata! Ora puoi creare un gruppo con /newgroup.",
    )
  end

  def self.handle_reject_user(bot, msg, chat_id, user_id)
    # ❌ Rimuovi l'utente dai pendenti
    Whitelist.remove_pending_request(user_id)

    # Rispondi alla callback query
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Richiesta rifiutata")

    # Modifica il messaggio originale
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: msg.message.message_id,
      text: "❌ Richiesta rifiutata per ID: #{user_id}",
    )

    # Notifica OPZIONALE all'utente rifiutato
    begin
      bot.api.send_message(
        chat_id: user_id,
        text: "🚫 La tua richiesta di accesso è stata rifiutata dall'amministratore.",
      )
    rescue => e
      puts "⚠️ Impossibile notificare utente rifiutato: #{e.message}"
    end
  end

  def self.handle_show_list(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "📋 Mostro la lista")
    # 🔥 MODIFICA: Passa topic_id
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, nil, 0, topic_id)
  end

  def self.handle_add_replace_foto(bot, msg, chat_id, item_id, gruppo_id, topic_id = 0)
    user_id = msg.from.id  # AGGIUNTA: Ottieni l'user_id dal messaggio
    user_name = msg.from.first_name

    DB.execute(
      "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, item_id, initiator_id, topic_id, creato_il) VALUES (?, ?, ?, ?, ?, ?, datetime('now'))",
      [
        chat_id,
        "upload_foto:#{user_name}:#{gruppo_id}:#{item_id}",
        gruppo_id,
        item_id,
        user_id,
        topic_id,  # 🔥 MODIFICA: Aggiungi topic_id
      ]
    )

    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "📸 Inviami la foto che vuoi associare a questo articolo...",
    )
  end

  def self.handle_remove_foto(bot, msg, chat_id, user_id, item_id, gruppo_id, topic_id = 0)
    Lista.rimuovi_immagine(item_id)

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "✅ Foto rimossa",
    )
    # 🔥 MODIFICA: Passa topic_id
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_foto_menu(bot, msg, chat_id, item_id, gruppo_id, topic_id = 0)
    has_image = Lista.ha_immagine?(item_id)

    if has_image
      buttons = [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "👁️ Visualizza foto",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "view_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🔄 Sostituisci foto",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "replace_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "🗑️ Rimuovi foto",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "remove_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
      ]
    else
      buttons = [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "📷 Aggiungi foto",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "add_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(
            text: "❌ Annulla",
            # 🔥 MODIFICA: Aggiungi topic_id
            callback_data: "cancel_foto:#{item_id}:#{gruppo_id}:#{topic_id}",
          ),
        ],
      ]
    end

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: buttons)

    bot.api.answer_callback_query(callback_query_id: msg.id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "📸 *Gestione foto per l'articolo*",
      parse_mode: "Markdown",
      reply_markup: markup,
    )
  end

  def self.handle_toggle(bot, msg, item_id, gruppo_id, topic_id = 0)
    item = DB.get_first_row("SELECT i.*, u.first_name, u.last_name, un.initials 
                          FROM items i
                          LEFT JOIN user_names u ON i.creato_da = u.user_id
                          LEFT JOIN user_names un ON un.user_id = ?
                          WHERE i.id = ?", [msg.from.id, item_id])

    if item
      # recupero la sigla dell'utente che ha fatto il toggle
      initials = item["initials"] || (item["first_name"]&.chars&.first || "U")
      current = item["comprato"]

      if current.nil? || current.strip == ""
        # non comprato → segno come comprato da questo utente
        DB.execute("UPDATE items SET comprato = ? WHERE id = ?", [initials, item_id])
        status = "✅"
        info = "#{item["nome"]} comprato da #{initials}"

        # AGGIORNA STORICO: incrementa conteggio
        StoricoManager.aggiorna_da_toggle(item["nome"], gruppo_id, 1)
      else
        # già comprato → lo resetto
        DB.execute("UPDATE items SET comprato = NULL WHERE id = ?", [item_id])
        status = "📄"
        info = "#{item["nome"]} di nuovo da comprare"

        # AGGIORNA STORICO: decrementa conteggio
        StoricoManager.aggiorna_da_toggle(item["nome"], gruppo_id, -1)
      end

      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: info,
        show_alert: true,
      )

      # 🔥 MODIFICA: Passa topic_id
      KeyboardGenerator.genera_lista(bot, msg.message.chat.id, gruppo_id, msg.from.id, msg.message.message_id, 0, topic_id)
    else
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "❌ Item non trovato",
      )
    end
  end

  # Nuovo metodo per gestire lo storico articoli
  def self.aggiorna_storico_articolo(nome_articolo, gruppo_id, incremento)
    # Normalizza il nome (lowercase per evitare duplicati)
    nome_normalizzato = nome_articolo.downcase.strip

    # Cerca o crea record storico
    storico = DB.get_first_row(
      "SELECT * FROM storico_articoli WHERE nome = ? AND gruppo_id = ?",
      [nome_normalizzato, gruppo_id]
    )

    if storico
      # Aggiorna record esistente
      nuovo_conteggio = [storico["conteggio"] + incremento, 0].max # non negativo
      DB.execute(
        "UPDATE storico_articoli SET conteggio = ?, ultima_aggiunta = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        [nuovo_conteggio, incremento > 0 ? Time.now.to_s : storico["ultima_aggiunta"], storico["id"]]
      )
    else
      # Crea nuovo record (solo se incremento positivo)
      if incremento > 0
        DB.execute(
          "INSERT INTO storico_articoli (nome, gruppo_id, conteggio, ultima_aggiunta) VALUES (?, ?, ?, ?)",
          [nome_normalizzato, gruppo_id, 1, Time.now.to_s]
        )
      end
    end
  end

  def self.handle_toggle_view_mode(bot, msg, chat_id, user_id, gruppo_id, topic_id = 0)
    new_mode = Preferences.toggle_view_mode(user_id)

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: new_mode == "text_only" ? "📄 Modalità testo" : "📱 Modalità compatta",
    )

    # 🔥 MODIFICA: Passa topic_id
    KeyboardGenerator.genera_lista(bot, chat_id, gruppo_id, user_id, msg.message.message_id, 0, topic_id)
  end

  def self.handle_aggiungi(bot, msg, chat_id, gruppo_id, topic_id = 0)
    # Se msg proviene da una CallbackQuery, l'utente è in msg.from
    # Se msg è un Message standard, è lo stesso.
    user_id = msg.from.id
    user_name = msg.from.first_name
    action = "add:#{user_name}"

    # 1. Salvataggio Azione Pendente
    begin
      query = "INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id, initiator_id, creato_il) VALUES (?, ?, ?, ?, ?, datetime('now'))"
      DB.execute(query, [chat_id, topic_id, action, gruppo_id, user_id])
      puts "✅ SQL SUCCESS: Azione salvata per il chat #{chat_id} topic #{topic_id}"
    rescue => e
      puts "❌ SQL ERROR: #{e.message}"
    end

    # Rispondi alla callback se è una query per togliere l'orologio dal bottone
    bot.api.answer_callback_query(callback_query_id: msg.id) if msg.respond_to?(:id)

    # 2. Invio istruzioni
    # Recuperiamo il nome del topic per rendere il messaggio più chiaro
    topic_name = DB.get_first_value("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [chat_id, topic_id]) || "questo reparto"
    text = "✍️ <b>#{user_name}</b>, scrivi gli articoli per <b>#{topic_name}</b>:"

    begin
      # Calcolo del thread: se chat_id < 0 (gruppo) e topic_id > 0, lo passiamo.
      # Se siamo in chat privata (chat_id > 0), thread_id deve essere nil.
      target_thread = (chat_id < 0 && topic_id != 0) ? topic_id : nil

      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: target_thread,
        text: text,
        parse_mode: "HTML",
      )
      puts "DEBUG SEND: Istruzioni inviate a chat #{chat_id} (thread: #{target_thread || "0/Privato"})"
    rescue => e
      puts "❌ API ERROR in handle_aggiungi: #{e.message}"
    end
  end

  def self.handle_cancel_foto(bot, msg, chat_id)
    bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌ Operazione annullata")
    bot.api.delete_message(chat_id: chat_id, message_id: msg.message.message_id)
  end

  def self.handle_info(bot, msg, item_id, gruppo_id, topic_id = 0)
    item = Lista.trova(item_id)
    if item
      # Se il campo 'comprato' è vuoto → da comprare, altrimenti contiene la sigla
      stato = item["comprato"].to_s.strip.empty? ? "📄 Da comprare" : "✅ Comprato da #{item["comprato"]}"

      # Mostriamo il nome e lo stato
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "#{item["nome"]} - #{stato}",
        show_alert: true,
      )
    else
      bot.api.answer_callback_query(
        callback_query_id: msg.id,
        text: "❌ Articolo non trovato",
      )
    end
  end

  def self.handle_show_checklist(bot, msg, chat_id, user_id, gruppo_id, topic_id)
    require "ostruct"

    # Crea un messaggio fittizio con i dati necessari
    fake_message = OpenStruct.new(
      chat: OpenStruct.new(id: chat_id),
      from: msg.from,
      message_thread_id: topic_id,
    )

    StoricoManager.genera_checklist(bot, fake_message, gruppo_id, topic_id)

    bot.api.answer_callback_query(
      callback_query_id: msg.id,
      text: "📋 Checklist caricata",
    )
  end

  def self.gestisci_chiusura_ui(bot, msg, callback_data)
    if callback_data =~ /^ui_close:(-?\d+):(\d+)$/
      chat_id = $1.to_i
      topic_id = $2.to_i

      puts "🧹 [UI] Chiudi messaggio chat #{chat_id} topic #{topic_id}"

      begin
        bot.api.delete_message(
          chat_id: chat_id,
          message_thread_id: topic_id > 0 ? topic_id : nil,
          message_id: msg.message.message_id,
        )
        bot.api.answer_callback_query(callback_query_id: msg.id)
      rescue => e
        puts "❌ Errore chiusura UI: #{e.message}"
        bot.api.answer_callback_query(callback_query_id: msg.id, text: "❌")
      end

      return true
    end

    false
  end
end
