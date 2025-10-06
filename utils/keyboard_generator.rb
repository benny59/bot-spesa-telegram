# utils/keyboard_generator.rb
require_relative "../models/lista"
require_relative "../models/preferences"
require_relative "../db"

class KeyboardGenerator
  def self.genera_lista(bot, chat_id, gruppo_id, user_id, message_id = nil)
    view_mode = Preferences.get_view_mode(user_id)

    if view_mode == "text_only"
      genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id)
    else
      genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id)
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
                                                              # 🔴 NUOVO: Aggiungi riga con "Chiudi"
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
  def self.genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id = nil)
    lista = Lista.tutti(gruppo_id)
    righe = lista.map do |item|
      initials = item["user_initials"] || item["initials"] || "U"

      # ✅ Se comprato contiene sigla, testo barrato + icona
      if item["comprato"] && !item["comprato"].empty?
        testo_item = "~#{item["nome"]}~"
        comprato_icon = "✅(#{item["comprato"]})"
      else
        testo_item = item["nome"]
        comprato_icon = ""
      end

      # 📸 se ha immagine, 📷 altrimenti
      photo_icon = Lista.ha_immagine?(item["id"]) ? "📸" : "📷"

      # ℹ️ con icona comprato
      info_btn = "ℹ️"  # Rimuoviamo eventuale icon check qui, solo info
      info_btn = item["comprato"].to_s.strip.empty? ? "ℹ️" : "ℹ️✅#{item["comprato"]}"

      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: testo_item,
          callback_data: "comprato:#{item["id"]}:#{gruppo_id}",
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: info_btn,
          callback_data: "info:#{item["id"]}:#{gruppo_id}", # <-- callback separato
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

    righe << [
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
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "💳 Carte", callback_data: "mostra_carte:#{gruppo_id}"),
    ]

    # 🔴 NUOVO: Aggiungi riga con solo "Chiudi"
    righe << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "checklist_close:#{chat_id}",
      ),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe)

    if message_id
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: message_id,
        text: "Lista della spesa:",
        reply_markup: markup,
        parse_mode: "MarkdownV2",
      )
    else
      bot.api.send_message(
        chat_id: chat_id,
        text: "Lista della spesa:",
        reply_markup: markup,
        parse_mode: "MarkdownV2",
      )
    end
  rescue Telegram::Bot::Exceptions::ResponseError => e
    if e.message&.include?("message is not modified")
      puts "⚠️ Messaggio non modificato (nessun cambiamento)"
    else
      raise e
    end
  end
end
