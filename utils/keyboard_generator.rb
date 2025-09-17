# utils/keyboard_generator.rb
require_relative '../models/lista'
require_relative '../models/preferences'
require_relative '../db'

class KeyboardGenerator
  def self.genera_lista(bot, chat_id, gruppo_id, user_id, message_id = nil)
    view_mode = Preferences.get_view_mode(user_id)
    
    if view_mode == 'text_only'
      genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id)
    else
      genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id)
    end
  end

def self.genera_lista_testo(bot, chat_id, gruppo_id, user_id, message_id = nil)
  lista = Lista.tutti(gruppo_id)
  
  text = "<b>🛒 Lista della spesa (solo testo):</b>\n\n"
  lista.each do |item|
    initials = item['user_initials'] || item['initials'] || "U"
    autore = "#{initials} -> "
    
    comprato_icon = item['comprato'] == 1 ? '  ✅' : ''
    photo_icon = Lista.ha_immagine?(item['id']) ? '  📸' : ''
    
    text += "#{autore}#{item['nome']}#{comprato_icon}#{photo_icon}\n"
  end

  markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [
    [
          Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "➕ Aggiungi",
        callback_data: "aggiungi:#{gruppo_id}"
      ),

      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "📱 Modalità compatta",
        callback_data: "toggle_view_mode:#{gruppo_id}"
      )
    ]
  ])

  if message_id
    bot.api.edit_message_text(
      chat_id: chat_id,
      message_id: message_id,
      text: text,
      reply_markup: markup,
      parse_mode: "HTML"  # Cambiato a HTML
    )
  else
    bot.api.send_message(
      chat_id: chat_id,
      text: text,
      reply_markup: markup,
      parse_mode: "HTML"  # Cambiato a HTML
    )
  end
end

  def self.genera_lista_compatta(bot, chat_id, gruppo_id, user_id, message_id = nil)
    lista = Lista.tutti(gruppo_id)
    righe = lista.map do |item|
      # USA le iniziali direttamente dal database
      initials = item['user_initials'] || item['initials'] || "U"
      
      testo_item = item['comprato'] == 1 ? "~#{item['nome']}~" : item['nome']
      
      # Icona per acquistato
      comprato_icon = item['comprato'] == 1 ? "✅" : ""
      
      # Icona per foto (📸 con flash = ha foto, 📷 senza flash = no foto)
      has_photo = Lista.ha_immagine?(item['id'])
      photo_icon = has_photo ? "📸" : "📷"
      
      # Secondo tasto: informazioni + icona acquistato
      info_btn = "#{comprato_icon}ℹ️".strip

      [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: testo_item,
          callback_data: "comprato:#{item['id']}:#{gruppo_id}"
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: info_btn,
          callback_data: "toggle:#{item['id']}:#{gruppo_id}"
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: photo_icon,
          callback_data: "foto_menu:#{item['id']}:#{gruppo_id}"
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{initials}-❌",
          callback_data: "cancella:#{item['id']}:#{gruppo_id}"
        )
      ]
    end

    righe << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "➕ Aggiungi",
        callback_data: "aggiungi:#{gruppo_id}"
      ),
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "📄 Modalità",
        callback_data: "toggle_view_mode:#{gruppo_id}"
      ),

      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🧹 Cancella tutti",
        callback_data: "cancella_tutti:#{gruppo_id}"
      )
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe)

    if message_id
      bot.api.edit_message_text(
        chat_id: chat_id,
        message_id: message_id,
        text: "Lista della spesa:",
        reply_markup: markup,
        parse_mode: "MarkdownV2"
      )
    else
      bot.api.send_message(
        chat_id: chat_id,
        text: "Lista della spesa:",
        reply_markup: markup,
        parse_mode: "MarkdownV2"
      )
    end
  end
end
