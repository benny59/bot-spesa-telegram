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
    g_id = gruppo_id.to_i
    t_id = topic_id.to_i

    total_pages = (items.size.to_f / ITEMS_PER_PAGE).ceil
    total_pages = 1 if total_pages == 0
    current_page = [0, [page, total_pages - 1].min].max

    start_index = current_page * ITEMS_PER_PAGE
    page_items = items[start_index, ITEMS_PER_PAGE] || []

    keyboard = []

    page_items.each do |item|
      # Determina se è comprato
      is_comprato = item["comprato"] && !item["comprato"].to_s.empty?

      # Recupera iniziali
      autore = item["autore_init"] || "??"
      buyer = item["buyer_init"]

      # 1. Testo dell'item (Pulito, senza ✅/⚪)
      # Se vuoi un tocco di classe, se è comprato lo mostriamo sbarrato
      item_text = is_comprato ? "<s>#{item["nome"]}</s>" : item["nome"]
      # Nota: InlineButtons non supportano sempre HTML nel testo del tasto,
      # quindi se il barrato non appare, usa solo item['nome']

      # 2. Etichetta del Cestino
      # Layout: 🗑️ [Autore] oppure 🗑️ [Autore] ✅ [Buyer]
      del_label = "🗑️ #{autore}"
      del_label += " ✅ #{buyer}" if is_comprato

      cb_data = "mycomprato:#{item["id"]}:#{g_id}:#{t_id}:#{current_page}:0"
      cb_del = "delete_item:#{item["id"]}:#{g_id}:#{t_id}:#{current_page}"

      keyboard << [
        Telegram::Bot::Types::InlineKeyboardButton.new(text: item["nome"], callback_data: cb_data),
        Telegram::Bot::Types::InlineKeyboardButton.new(text: del_label, callback_data: cb_del),
      ]
    end

    # Navigazione: Iniettiamo g_id e t_id per non perdere il contesto al cambio pagina
    if total_pages > 1
      nav = []
      nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "⬅️ Prec.", callback_data: "ui_page:#{g_id}:#{t_id}:#{current_page - 1}") if current_page > 0
      nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "Succ. ➡️", callback_data: "ui_page:#{g_id}:#{t_id}:#{current_page + 1}") if current_page < total_pages - 1
      keyboard << nav
    end

    # Controlli: Svuota, Carte e Chiudi devono conoscere il contesto
    keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "🧹 Svuota", callback_data: "ui_cleanup:#{g_id}:#{t_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "💳 Carte", callback_data: "ui_cards:#{g_id}:#{t_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{g_id}:#{t_id}"),
    ]

    # Header in HTML per evitare problemi di parsing
    text = "🛒 <b>#{nome_target}</b>\n"
    text += "📄 Pagina #{current_page + 1} di #{total_pages} (<i>#{items.size} elementi</i>)"

    { text: text, markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard) }
  end

  def self.show_private_keyboard(bot, chat_id,context)
    puts "📟 [DEBUG] Visualizzazione tastiera privata (con switch gruppo) per: #{chat_id}"
etichetta_lista = "🛒 LISTA  #{context.nome_contesto_pulito}"
    puts "etichetta_lista #{etichetta_lista}"

    keyboard = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
      keyboard: [
        [
          Telegram::Bot::Types::KeyboardButton.new(text: etichetta_lista),
          Telegram::Bot::Types::KeyboardButton.new(text: "➕ AGGIUNGI PRODOTTO"),
        ],
        [
          Telegram::Bot::Types::KeyboardButton.new(text: "📋 I MIEI ARTICOLI"),
          Telegram::Bot::Types::KeyboardButton.new(text: "💳 LE MIE CARTE"),
        ],
        [
          Telegram::Bot::Types::KeyboardButton.new(text: "📦 TUTTI GLI ARTICOLI"),
          Telegram::Bot::Types::KeyboardButton.new(text: "⚙️ IMPOSTA GRUPPO"), # Richiama /private
        ],
      ],
      resize_keyboard: true,
      one_time_keyboard: false,
    )

   bot.api.send_message(
      chat_id: chat_id,
      text: "passato a #{etichetta_lista}",
      reply_markup: keyboard,
      parse_mode: "Markdown",
    )
  end

  def self.show_group_selector(bot, user_id, message_id = nil)
    # 1. Recupero la config attuale dell'utente per evidenziare la scelta attiva
    current_config = DataManager.carica_config_utente(user_id)

    # 2. Utilizzo il metodo esistente nel DataManager per ottenere la lista pulita
    destinazioni = DataManager.prendi_destinazioni_censite(user_id)

    # 3. Costruzione dei bottoni
    keyboard = destinazioni.map do |dest|
      # Controllo se questa destinazione è quella attualmente attiva nella config
      is_active = if dest["chat_id"] == 0
          current_config && current_config["db_id"].to_i == 0
        else
          current_config &&
          current_config["db_id"].to_i == dest["chat_id"].to_i &&
          current_config["topic_id"].to_i == dest["topic_id"].to_i
        end

      prefix = is_active ? "✅ " : ""

      [Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{prefix}#{dest["nome"]}",
        # Usiamo chat_id restituito dal DB che rappresenta l'ID interno del gruppo
        callback_data: "private_set:#{dest["chat_id"]}:#{user_id}:#{dest["topic_id"]}",
      )]
    end

    # Tasto di chiusura
    keyboard << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{user_id}:0")]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
    text = "🔒 **Gestione Liste**\nScegli quale lista gestire in questa chat privata:"

    # 4. Invio o modifica del messaggio
    if message_id
      bot.api.edit_message_text(chat_id: user_id, message_id: message_id, text: text, reply_markup: markup, parse_mode: "Markdown")
    else
      bot.api.send_message(chat_id: user_id, text: text, reply_markup: markup, parse_mode: "Markdown")
    end
  rescue => e
    puts "❌ [UI ERROR] Errore selettore: #{e.message}" unless e.message.include?("not modified")
  end
end
