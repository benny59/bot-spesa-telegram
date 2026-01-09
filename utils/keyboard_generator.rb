# utils/keyboard_generator.rb
require_relative "../models/lista"
require_relative "../models/preferences"
require_relative "../db"

class KeyboardGenerator
  ITEMS_PER_PAGE = 10  # Numero di elementi per pagina
  MAX_BUTTONS_PER_PAGE = 90  # sicurezza, sotto il limite di Telegram

  # utils/keyboard_generator.rb - Modifica il metodo genera_lista
  # utils/keyboard_generator.rb

  # Aggiungiamo target_thread_id alla fine
  def self.genera_lista(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0, topic_id = 0, target_thread_id = nil)
    view_mode = Preferences.get_view_mode(user_id)

    if view_mode == "text_only"
      genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id, page, topic_id, target_thread_id)
    else
      # Passiamo l'8° argomento al metodo compatto
      genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id, page, topic_id, target_thread_id)
    end
  end

  def self.genera_testo_lista(items, gruppo_id, page = 0, total_pages = 1, total_elements = nil)
    total_elements ||= items.size

    text = "<b>🛒 Lista della spesa - Pagina #{page + 1}/#{total_pages} (#{total_elements} elementi):</b>\n\n"

    if items.empty?
      text += "📭 Nessun elemento in questa pagina\n"
    else
      items.each do |item|
        initials = item["user_initials"] || item["initials"] || "U"
        autore = "#{initials} -> "

        # ✅ Se comprato contiene sigla, mostro ✅(sigla)
        comprato_icon = item["comprato"] && !item["comprato"].empty? ? " ✅(#{item["comprato"]})" : ""

        # 📸 se c'è immagine
        photo_icon = Lista.ha_immagine?(item["id"]) ? "  📸" : ""

        text += "#{autore}#{item["nome"]}#{comprato_icon}#{photo_icon}\n"
      end
    end

    return text
  end

  # ===================== LISTA SOLO TESTO =====================
  def self.genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0, topic_id = 0, target_thread_id = nil)
    lista = Lista.tutti(gruppo_id, topic_id)

    total_pages = (lista.size.to_f / ITEMS_PER_PAGE).ceil
    page = [page, total_pages - 1].min
    page = [page, 0].max

    start_index = page * ITEMS_PER_PAGE
    end_index = [start_index + ITEMS_PER_PAGE - 1, lista.size - 1].min
    lista_pagina = lista[start_index..end_index] || []

    text = "<b>🛒 Lista della spesa (solo testo) - Pagina #{page + 1}/#{total_pages} (#{lista.size} elementi):</b>\n\n"

    if lista_pagina.empty?
      text += "📭 Nessun elemento in questa pagina\n"
    else
      lista_pagina.each do |item|
        initials = item["user_initials"] || item["initials"] || "U"
        autore = "#{initials} -> "

        # ✅ Se comprato contiene sigla, mostro ✅(sigla)
        comprato_icon = item["comprato"] && !item["comprato"].empty? ? " ✅(#{item["comprato"]})" : ""

        # 📸 se c'è immagine
        photo_icon = Lista.ha_immagine?(item["id"]) ? "  📸" : ""

        text += "#{autore}#{item["nome"]}#{comprato_icon}#{photo_icon}\n"
      end
    end

    # MODIFICA: Aggiungi bottoni di navigazione per paginazione
    nav_buttons = []
    if total_pages > 1
      row = []

      if page > 0
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️ Pagina #{page}",
          callback_data: "lista_page:#{gruppo_id}:#{page - 1}",
        )
      end

      row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{page + 1}/#{total_pages}",
        callback_data: "noop",
      )

      if page < total_pages - 1
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "Pagina #{page + 2} ▶️",
          callback_data: "lista_page:#{gruppo_id}:#{page + 1}",
        )
      end

      nav_buttons = [row] if row.any?
    end

    # MODIFICA: Combina bottoni di navigazione con quelli di controllo
    inline_keyboard = nav_buttons + [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "➕ Aggiungi",
          callback_data: "aggiungi:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📱 Modalità compatta",
          callback_data: "toggle_view_mode:#{gruppo_id}:#{topic_id}", # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "💳 Carte",
          callback_data: "mostra_carte:#{gruppo_id}:#{topic_id}",     # Aggiunto topic_id
        ),
      ],
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "❌ Chiudi",
          callback_data: "checklist_close:#{chat_id}",
        ),
      ],
    ]

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
      # MODIFICA: Usa message_thread_id se topic_id > 0
      if topic_id && topic_id > 0
        bot.api.send_message(
          chat_id: chat_id,
          message_thread_id: topic_id,
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
  end

  # Metodo helper specifico per handle_myitems che formatta gli articoli con tutte le icone
  def self.formatta_articoli_per_myitems(items)
    text = ""

    if items.empty?
      text += "📭 Nessun articolo\n"
    else
      items.each do |item|
        initials = item["user_initials"] || item["initials"] || "U" # <- Questo "U" è il colpevole
        autore = "#{initials} -> "

        # ✅ Se comprato contiene sigla, mostro ✅(sigla)
        comprato_icon = item["comprato"] && !item["comprato"].empty? ? " ✅(#{item["comprato"]})" : ""

        # 📸 se c'è immagine
        photo_icon = Lista.ha_immagine?(item["id"]) ? "  📸" : ""

        text += "#{autore}#{item["nome"]}#{comprato_icon}#{photo_icon}\n"
      end
    end

    return text
  end

  # ===================== LISTA COMPATTA =====================
  def self.genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0, topic_id = 0, target_thread_id = nil)

    # MODIFICA: Passa topic_id a Lista.tutti
    lista = Lista.tutti(gruppo_id, topic_id)

    # Calcola paginazione
    total_pages = (lista.size.to_f / ITEMS_PER_PAGE).ceil
    page = [page, total_pages - 1].min
    page = [page, 0].max

    start_index = page * ITEMS_PER_PAGE
    end_index = [start_index + ITEMS_PER_PAGE - 1, lista.size - 1].min

    # Prendi solo gli elementi della pagina corrente
    lista_pagina = lista[start_index..end_index] || []

    righe = []
    lista_pagina.each do |item|
      initials = item["user_initials"] || item["initials"] || "U"

      if item["comprato"] && !item["comprato"].empty?
        escaped_comprato = item["comprato"].gsub("(", '\\(').gsub(")", '\\)')
        testo_item = "~#{item["nome"]}~"
        comprato_icon = "✅(#{escaped_comprato})"
      else
        testo_item = item["nome"]
        comprato_icon = ""
      end

      photo_icon = Lista.ha_immagine?(item["id"]) ? "📸" : "📷"

      info_btn = if item["comprato"].to_s.strip.empty?
          "ℹ️"
        else
          escaped_comprato = item["comprato"].gsub("(", '\\(').gsub(")", '\\)')
          "ℹ️✅#{escaped_comprato}"
        end

      # Prima riga: solo l'item
      righe << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: testo_item,
          callback_data: "comprato:#{item["id"]}:#{gruppo_id}:#{topic_id}",
        ),
      ]

      # Seconda riga: bottoni info, photo, delete
      righe << [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: info_btn,
          callback_data: "info:#{item["id"]}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: photo_icon,
          callback_data: "foto_menu:#{item["id"]}:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{initials}-❌",
          callback_data: "cancella:#{item["id"]}:#{gruppo_id}:#{topic_id}",
        ),
      ]
    end

    # Bottoni di navigazione se necessario
    nav_buttons = []
    if total_pages > 1
      row = []

      # Bottone indietro
      if page > 0
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️ Pagina #{page}",
          callback_data: "lista_page:#{gruppo_id}:#{page - 1}:#{topic_id}",
        )
      end

      # Bottone pagina corrente (sempre presente)
      row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{page + 1}/#{total_pages}",
        callback_data: "noop",
      )

      # Bottone avanti
      if page < total_pages - 1
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "Pagina #{page + 2} ▶️",
          callback_data: "lista_page:#{gruppo_id}:#{page + 1}:#{topic_id}",
        )
      end

      nav_buttons = [row] if row.any?
    end

    # Bottoni di controllo
    control_buttons = [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "➕ Aggiungi",
          callback_data: "aggiungi:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📄 Modalità",
          callback_data: "toggle_view_mode:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🧹 Cancella tutti",
          callback_data: "cancella_tutti:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "💳 Carte",
          callback_data: "mostra_carte:#{gruppo_id}:#{topic_id}",
        ),
      ],
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📋 Checklist",
          callback_data: "show_checklist:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🕒 Storico",
          callback_data: "show_storico:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "❌ Chiudi",
          callback_data: "checklist_close:#{chat_id}:#{topic_id}",
        ),
      ],
    ]

    # Combina tutte le righe

    inline_keyboard = righe + nav_buttons + control_buttons
    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # 1. Determiniamo il chat_id del GRUPPO (quello reale, negativo)
    real_group_chat_id = if chat_id.to_i > 0
        # Siamo in privato: recuperiamo il chat_id del gruppo dal DB
        row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{chat_id}"])
        config = JSON.parse(row["value"]) rescue nil if row
        config ? config["chat_id"] : nil
      else
        # Siamo già nel gruppo
        chat_id
      end

    # 2. Recuperiamo il nome del Gruppo e del Topic in un'unica query (se possibile) o separatamente
    nome_gruppo = "Gruppo Sconosciuto"
    topic_label = (topic_id.to_i == 0) ? "Generale" : "Topic #{topic_id}"

    if real_group_chat_id
      # Recupero nome gruppo
      g_nome = DB.get_first_value("SELECT nome FROM gruppi WHERE chat_id = ?", [real_group_chat_id])
      nome_gruppo = g_nome if g_nome

      # Recupero nome topic
      t_nome = DB.get_first_value("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [real_group_chat_id, topic_id])
      topic_label = t_nome if t_nome
    end

    # 3. Componiamo il testo dell'intestazione
    # Esempio: 🛒 <b>Casa (Generale)</b>
    text_message = "🛒 <b>#{nome_gruppo} (#{topic_label})</b>\n"
    text_message += "📄 Pagina #{page + 1}/#{total_pages} (#{lista.size} elementi)"

    # 1. Calcoliamo il thread di destinazione reale
    # Se siamo in privato (chat_id > 0), il thread deve essere SEMPRE nil
    # Se siamo in gruppo (chat_id < 0), usiamo target_thread_id o topic_id
    actual_thread_id = (chat_id.to_i > 0) ? nil : (target_thread_id || topic_id)

    if message_id
      begin
        bot.api.edit_message_text(
          chat_id: chat_id,
          message_id: message_id,
          text: text_message,
          reply_markup: markup,
          parse_mode: "HTML",
        )
        return true
      rescue Telegram::Bot::Exceptions::ResponseError => e
        if e.message&.include?("message is not modified")
          begin
            bot.api.edit_message_reply_markup(
              chat_id: chat_id,
              message_id: message_id,
              reply_markup: markup,
            )
            return true
          rescue Telegram::Bot::Exceptions::ResponseError
            return false
          end
        else
          raise e
        end
      end
    else
      # 2. INVIO FISICO
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: (actual_thread_id.to_i > 0 ? actual_thread_id : nil),
        text: text_message,
        reply_markup: markup,
        parse_mode: "HTML",
      )
      return true
    end
  end

  # ===================== LISTA COMPATTA =====================
  def self.genera_lista_compatta_old(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0, topic_id = 0, target_thread_id = nil)
    # MODIFICA: Passa topic_id a Lista.tutti
    lista = Lista.tutti(gruppo_id, topic_id)

    # Calcola paginazione
    total_pages = (lista.size.to_f / ITEMS_PER_PAGE).ceil
    page = [page, total_pages - 1].min
    page = [page, 0].max

    start_index = page * ITEMS_PER_PAGE
    end_index = [start_index + ITEMS_PER_PAGE - 1, lista.size - 1].min

    # Prendi solo gli elementi della pagina corrente
    lista_pagina = lista[start_index..end_index] || []

    righe = lista_pagina.map do |item|
      initials = item["user_initials"] || item["initials"] || "U"

      if item["comprato"] && !item["comprato"].empty?
        escaped_comprato = item["comprato"].gsub("(", '\\(').gsub(")", '\\)')
        testo_item = "~#{item["nome"]}~"
        comprato_icon = "✅(#{escaped_comprato})"
      else
        testo_item = item["nome"]
        comprato_icon = ""
      end

      photo_icon = Lista.ha_immagine?(item["id"]) ? "📸" : "📷"

      info_btn = if item["comprato"].to_s.strip.empty?
          "ℹ️"
        else
          escaped_comprato = item["comprato"].gsub("(", '\\(').gsub(")", '\\)')
          "ℹ️✅#{escaped_comprato}"
        end

      # 🔥 MODIFICA IMPORTANTE: Aggiungi topic_id a tutti i callback_data
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: testo_item,
          callback_data: "comprato:#{item["id"]}:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: info_btn,
          callback_data: "info:#{item["id"]}:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: photo_icon,
          callback_data: "foto_menu:#{item["id"]}:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{initials}-❌",
          callback_data: "cancella:#{item["id"]}:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
      ]
    end

    # Bottoni di navigazione se necessario
    nav_buttons = []
    if total_pages > 1
      row = []

      # Bottone indietro
      if page > 0
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️ Pagina #{page}",
          callback_data: "lista_page:#{gruppo_id}:#{page - 1}:#{topic_id}",  # Aggiunto topic_id
        )
      end

      # Bottone pagina corrente (sempre presente)
      row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{page + 1}/#{total_pages}",
        callback_data: "noop",
      )

      # Bottone avanti
      if page < total_pages - 1
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "Pagina #{page + 2} ▶️",
          callback_data: "lista_page:#{gruppo_id}:#{page + 1}:#{topic_id}",  # Aggiunto topic_id
        )
      end

      nav_buttons = [row] if row.any?
    end

    # Bottoni di controllo
    control_buttons = [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "➕ Aggiungi",
          callback_data: "aggiungi:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📄 Modalità",
          callback_data: "toggle_view_mode:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🧹 Cancella tutti",
          callback_data: "cancella_tutti:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "💳 Carte",
          callback_data: "mostra_carte:#{gruppo_id}:#{topic_id}",  # Aggiunto topic_id
        ),
      ],
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📋 Checklist",
          callback_data: "show_checklist:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🕒 Storico",
          callback_data: "show_storico:#{gruppo_id}:#{topic_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "❌ Chiudi",
          callback_data: "checklist_close:#{chat_id}:#{topic_id}",
        ),
      ],
    ]

    # Combina tutte le righe
    inline_keyboard = righe + nav_buttons + control_buttons

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # --- RECUPERO NOMI GRUPPO E TOPIC PER INTESTAZIONE ---

    # 1. Determiniamo il chat_id del GRUPPO (quello reale, negativo)
    real_group_chat_id = if chat_id.to_i > 0
        # Siamo in privato: recuperiamo il chat_id del gruppo dal DB
        row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{chat_id}"])
        config = JSON.parse(row["value"]) rescue nil if row
        config ? config["chat_id"] : nil
      else
        # Siamo già nel gruppo
        chat_id
      end

    # 2. Recuperiamo il nome del Gruppo e del Topic in un'unica query (se possibile) o separatamente
    nome_gruppo = "Gruppo Sconosciuto"
    topic_label = (topic_id.to_i == 0) ? "Generale" : "Topic #{topic_id}"

    if real_group_chat_id
      # Recupero nome gruppo
      g_nome = DB.get_first_value("SELECT nome FROM gruppi WHERE chat_id = ?", [real_group_chat_id])
      nome_gruppo = g_nome if g_nome

      # Recupero nome topic
      t_nome = DB.get_first_value("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [real_group_chat_id, topic_id])
      topic_label = t_nome if t_nome
    end

    # 3. Componiamo il testo dell'intestazione
    # Esempio: 🛒 <b>Casa (Generale)</b>
    text_message = "🛒 <b>#{nome_gruppo} (#{topic_label})</b>\n"
    text_message += "📄 Pagina #{page + 1}/#{total_pages} (#{lista.size} elementi)"

    # 1. Calcoliamo il thread di destinazione reale
    # Se siamo in privato (chat_id > 0), il thread deve essere SEMPRE nil
    # Se siamo in gruppo (chat_id < 0), usiamo target_thread_id o topic_id
    actual_thread_id = (chat_id.to_i > 0) ? nil : (target_thread_id || topic_id)

    if message_id
      begin
        bot.api.edit_message_text(
          chat_id: chat_id,
          message_id: message_id,
          text: text_message,
          reply_markup: markup,
          parse_mode: "HTML",
        )
        return true
      rescue Telegram::Bot::Exceptions::ResponseError => e
        if e.message&.include?("message is not modified")
          begin
            bot.api.edit_message_reply_markup(
              chat_id: chat_id,
              message_id: message_id,
              reply_markup: markup,
            )
            return true
          rescue Telegram::Bot::Exceptions::ResponseError
            return false
          end
        else
          raise e
        end
      end
    else
      # 2. INVIO FISICO
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: (actual_thread_id.to_i > 0 ? actual_thread_id : nil),
        text: text_message,
        reply_markup: markup,
        parse_mode: "HTML",
      )
      return true
    end
  end # fine genera_lista_compatta
end # fine classe
