# utils/keyboard_generator.rb
require_relative "../models/lista"
require_relative "../models/preferences"
require_relative "../db"

class KeyboardGenerator
  ITEMS_PER_PAGE = 10  # Numero di elementi per pagina
  MAX_BUTTONS_PER_PAGE = 90  # sicurezza, sotto il limite di Telegram

  def self.genera_lista(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0)
    view_mode = Preferences.get_view_mode(user_id)

    if view_mode == "text_only"
      # MODIFICA: Passa anche il parametro page a genera_lista_testo
      genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id, page)
    else
      genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id, page)
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
  def self.genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0)
    lista = Lista.tutti(gruppo_id)

    # MODIFICA: Aggiungi paginazione anche per la vista testo
    total_pages = (lista.size.to_f / ITEMS_PER_PAGE).ceil
    page = [page, total_pages - 1].min
    page = [page, 0].max

    start_index = page * ITEMS_PER_PAGE
    end_index = [start_index + ITEMS_PER_PAGE - 1, lista.size - 1].min
    lista_pagina = lista[start_index..end_index] || []

    # MODIFICA: Aggiorna il testo con informazioni sulla paginazione
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
          callback_data: "aggiungi:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📱 Modalità compatta",
          callback_data: "toggle_view_mode:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "💳 Carte",
          callback_data: "mostra_carte:#{gruppo_id}",
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
      bot.api.send_message(
        chat_id: chat_id,
        text: text,
        reply_markup: markup,
        parse_mode: "HTML",
      )
    end
  end

  # Metodo helper specifico per handle_myitems che formatta gli articoli con tutte le icone
  def self.formatta_articoli_per_myitems(items)
    text = ""

    if items.empty?
      text += "📭 Nessun articolo\n"
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

  # ===================== LISTA COMPATTA =====================
  def self.genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id = nil, page = 0)
    lista = Lista.tutti(gruppo_id)

    # Calcola paginazione - CORREZIONE: usa .min invece di .max
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

      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: testo_item,
          callback_data: "comprato:#{item["id"]}:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: info_btn,
          callback_data: "info:#{item["id"]}:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: photo_icon,
          callback_data: "foto_menu:#{item["id"]}:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{initials}-❌",
          callback_data: "cancella:#{item["id"]}:#{gruppo_id}",
        ),
      ]
    end

    # Bottoni di navigazione se necessario - CORREZIONE: struttura semplificata
    nav_buttons = []
    if total_pages > 1
      row = []

      # Bottone indietro
      if page > 0
        row << Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "◀️ Pagina #{page}",
          callback_data: "lista_page:#{gruppo_id}:#{page - 1}",
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
          callback_data: "lista_page:#{gruppo_id}:#{page + 1}",
        )
      end

      nav_buttons = [row] if row.any?
    end

    # Bottoni di controllo
    control_buttons = [
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "➕ Aggiungi",
          callback_data: "aggiungi:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "📄 Modalità",
          callback_data: "toggle_view_mode:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🧹 Cancella tutti",
          callback_data: "cancella_tutti:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "💳 Carte",
          callback_data: "mostra_carte:#{gruppo_id}",
        ),
      ],
      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "❌ Chiudi",
          callback_data: "checklist_close:#{chat_id}",
        ),
      ],
    ]

    # Combina tutte le righe
    inline_keyboard = righe + nav_buttons + control_buttons

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # Testo del messaggio
    text_message = "🛒 Lista della spesa - Pagina #{page + 1}/#{total_pages} (#{lista.size} elementi)"

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
          puts "⚠️ Messaggio non modificato (nessun cambiamento)"
          # Forza l'aggiornamento solo della tastiera
          begin
            bot.api.edit_message_reply_markup(
              chat_id: chat_id,
              message_id: message_id,
              reply_markup: markup,
            )
            return true
          rescue Telegram::Bot::Exceptions::ResponseError => e2
            puts "⚠️ Anche la tastiera non è modificata"
            return false
          end
        else
          raise e
        end
      end
    else
      bot.api.send_message(
        chat_id: chat_id,
        text: text_message,
        reply_markup: markup,
        parse_mode: "HTML",
      )
      return true
    end
  end
end
