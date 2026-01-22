# utils/keyboard_generator.rb
require "telegram/bot"

class KeyboardGenerator
  ITEMS_PER_PAGE = 10

  # utils/keyboard_generator.rb

  def self.tastiera_privata_fissa
    # Definiamo i tasti come semplici stringhe per la ReplyKeyboardMarkup
    kb = [
      ["🛒 LISTA", "➕ AGGIUNGI"],
      ["📋 I MIEI ARTICOLI", "⚙️ IMPOSTA GRUPPO"],
    ]

    Telegram::Bot::Types::ReplyKeyboardMarkup.new(
      keyboard: kb,
      resize_keyboard: true,
      one_time_keyboard: false,
    )
  end

  def self.tastiera_scelta_gruppo(destinazioni)
    kb = []
    destinazioni.each do |d|
      # Se chat_id è 0, è la lista personale
      prefix = d["chat_id"] == 0 ? "👤" : "👥"
      nome = d["nome"] || "Generale"

      kb << [Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{prefix} #{nome}",
        callback_data: "set_target:#{d["chat_id"]}:#{d["topic_id"]}",
      )]
    end
    Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: kb)
  end

  def self.genera_lista(items, gruppo_id, topic_id, page = 0, nome_target = "Lista")
    total_pages = (items.size.to_f / ITEMS_PER_PAGE).ceil
    total_pages = 1 if total_pages == 0
    current_page = [0, [page, total_pages - 1].min].max

    start_index = current_page * ITEMS_PER_PAGE
    page_items = items[start_index, ITEMS_PER_PAGE] || []

    keyboard = []

    # Bottoni Articoli
    # Bottoni Articoli
    page_items.each do |item|
      icon = (item["comprato"] && !item["comprato"].empty?) ? "✅" : "⚪"
      cb_data = "mycomprato:#{item["id"]}:#{gruppo_id}:#{topic_id}:#{current_page}:0"

      # Creiamo la riga con DUE bottoni
      row = [
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "#{icon} #{item["nome"]}",
          callback_data: cb_data,
        ),
        Telegram::Bot::Types::InlineKeyboardButton.new(
          text: "🗑️",
          callback_data: "delete_item:#{item["id"]}:#{gruppo_id}:#{topic_id}:#{current_page}",
        ),
      ]

      keyboard << row
    end

    # Navigazione
    nav = []
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "⬅️ Prec.", callback_data: "ui_page:#{gruppo_id}:#{topic_id}:#{current_page - 1}") if current_page > 0
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "Succ. ➡️", callback_data: "ui_page:#{gruppo_id}:#{topic_id}:#{current_page + 1}") if current_page < total_pages - 1
    keyboard << nav unless nav.empty?

    # Controlli
    keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "📋 Checklist", callback_data: "ui_checklist:#{gruppo_id}:#{topic_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "🧹 Svuota", callback_data: "ui_cleanup:#{gruppo_id}:#{topic_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{gruppo_id}:#{topic_id}"),
    ]

    text = "🛒 **#{nome_target}**\n"
    text += "📄 Pagina #{current_page + 1} di #{total_pages} (#{items.size} elementi)"

    { text: text, markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard) }
  end
end
