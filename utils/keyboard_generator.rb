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
      genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id)
    else
      genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id, page)
    end
  end

  # ===================== LISTA SOLO TESTO =====================
  def self.genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id = nil)
    lista = Lista.tutti(gruppo_id)

    text = "<b>🛒 Lista della spesa (solo testo):</b>\n\n"
    lista.each do |item|
      initials = item["user_initials"] || item["initials"] || "U"
      autore = "#{initials} -> "

      # ✅ Se comprato contiene sigla, mostro ✅(sigla)
      comprato_icon = item["comprato"] && !item["comprato"].empty? ? " ✅(#{item["comprato"]})" : ""

      # 📸 se c'è immagine
      photo_icon = Lista.ha_immagine?(item["id"]) ? "  📸" : ""

      text += "#{autore}#{item["nome"]}#{comprato_icon}#{photo_icon}\n"
    end

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
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
                                                            ])

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
      escaped_comprato = item["comprato"].gsub('(', '\\(').gsub(')', '\\)')
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
                 escaped_comprato = item["comprato"].gsub('(', '\\(').gsub(')', '\\)')
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
        callback_data: "mostra_carte:#{gruppo_id}"
      ),
    ],
    [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "checklist_close:#{chat_id}",
      ),
    ]
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
