# utils/keyboard_generator.rb
require "telegram/bot"

class KeyboardGenerator
  ITEMS_PER_PAGE = 10
  INLINE_TEXT_MAX_BYTES = 60

  # Telegram inline button text has tight limits. Keep labels short and strip
  # transport markers/URLs used for app-backward compatibility.
  def self.safe_item_label(raw_name, max_len = 52)
    label = raw_name.to_s
    label = label.gsub(/\[?YUKA_LINK\]?/i, " ")
    label = label.gsub(/https?:\/\/\S+/, "")
    label = label.gsub(/[\u0000-\u001F\u007F]/, " ")
    label = label.gsub(/\s+/, " ").strip
    label = "Prodotto Yuka" if label.empty?

    candidate = if label.length <= max_len
      label
    else
      "#{label[0, max_len - 3]}..."
    end

    clamp_inline_text(candidate)
  end

  def self.clamp_inline_text(text, max_bytes = INLINE_TEXT_MAX_BYTES)
    clean = text.to_s.scrub(" ").gsub(/[\u0000-\u001F\u007F]/, " ").gsub(/\s+/, " ").strip
    clean = "-" if clean.empty?
    return clean if clean.bytesize <= max_bytes

    bytes = clean.byteslice(0, max_bytes - 3)
    bytes = bytes.force_encoding("UTF-8").scrub("")
    bytes = bytes.gsub(/\s+$/, "")
    "#{bytes}..."
  end

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

  def self.genera_lista(items, gruppo_id, topic_id, page = 0, options = {})
    # Default delle opzioni
    opts = { nome_target: "Lista", is_group: false }.merge(options)
    nome_target = opts[:nome_target]

    # DEBUG TEMPORANEO:
    puts "DEBUG: Primo item ha_foto -> #{items.first["ha_foto"] if items.any?}"
    g_id = gruppo_id.to_i
    t_id = topic_id.to_i

    total_pages = (items.size.to_f / ITEMS_PER_PAGE).ceil
    total_pages = 1 if total_pages == 0
    current_page = [0, [page, total_pages - 1].min].max

    start_index = current_page * ITEMS_PER_PAGE
    page_items = items[start_index, ITEMS_PER_PAGE] || []

    keyboard = []

    page_items.each do |item|
      parsed = DataManager.parse_nome_categoria(item["nome"].to_s, item["categoria_id"], item["categoria_id"], g_id, t_id)
      nome_da_mostrare = parsed[:nome].to_s.strip
      nome_da_mostrare = item["nome"].to_s.strip if nome_da_mostrare.empty?
      nome_pulito = safe_item_label(nome_da_mostrare)
      is_comprato = item["comprato"] && !item["comprato"].to_s.empty?
      is_deleted = item["deleted"].to_i == 1
      is_unavailable = item["disponibile"].to_i == 0

      # La fotocamera è troppo allettante: usiamo un occhio nel nome item,
      # il pulsante foto rimane solo in fondo alla lista
      num_foto = item["ha_foto"].to_i
      foto_marker = num_foto > 0 ? " 👁" : ""
      display_name = (is_deleted || is_unavailable) ? "~~ #{nome_pulito} ~~" : nome_pulito
      display_name = "#{foto_marker}#{display_name}" unless display_name.empty?
      display_name = clamp_inline_text(display_name)

      autore = item["autore_init"] || "??"
      buyer = item["buyer_init"]

      # Bottone azione: solo cestino, senza icona foto
      if is_deleted
        del_label = "↩️ #{autore}"
      elsif is_unavailable
        del_label = "❌ #{autore}"
      else
        del_label = "🗑️ #{autore}"
      end
      del_label += " ✅ #{buyer}" if is_comprato && !is_deleted && !is_unavailable
      del_label = clamp_inline_text(del_label)

      cb_data = "mycomprato:#{item["id"]}:#{g_id}:#{t_id}:#{current_page}:0"
      cb_del = is_unavailable ? "toggle_disponibile:#{item["id"]}:#{g_id}:#{t_id}:#{current_page}" : "delete_item:#{item["id"]}:#{g_id}:#{t_id}:#{current_page}"

      keyboard << [
        Telegram::Bot::Types::InlineKeyboardButton.new(text: display_name, callback_data: cb_data),
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

    # --- AZIONI PRINCIPALI (Riga 1) ---

    keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "➕ Aggiungi", callback_data: "aggiungi:#{g_id}:#{t_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "💳 Carte", callback_data: "ui_cards:#{g_id}:#{t_id}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "🧹 Svuota", callback_data: "ui_cleanup:#{g_id}:#{t_id}"),

    ]
    # Se ci sono foto, il tasto 📸 prende il posto principale in questa riga

    if !opts[:is_group]
      # --- AZIONI SECONDARIE (Riga 2) ---
      row_secondary = [
        Telegram::Bot::Types::InlineKeyboardButton.new(text: "📋 Checklist", callback_data: "ui_checklist:#{g_id}:#{t_id}"),
        Telegram::Bot::Types::InlineKeyboardButton.new(text: "🕒 Storico", callback_data: "show_storico:#{g_id}:#{t_id}"),
      ]
      keyboard << row_secondary
    end
    # Uniamo "Vedi Foto" con i tasti di sistema per risparmiare righe verticali
    system_row = []

    ha_almeno_una_foto = items.any? { |i| i["ha_foto"].to_i > 0 }
    if ha_almeno_una_foto
      system_row << Telegram::Bot::Types::InlineKeyboardButton.new(text: "📸 Foto", callback_data: "show_photos:#{g_id}:#{t_id}")
    end

    system_row << Telegram::Bot::Types::InlineKeyboardButton.new(text: "🔄", callback_data: "ui_back_to_list:#{g_id}:#{t_id}")
    system_row << Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{g_id}:#{t_id}")

    keyboard << system_row

    # Header in HTML
    text = "🛒 <b>#{nome_target}</b>\n"
    text += "📄 Pagina <b>#{current_page + 1}</b> di #{total_pages} (<i>#{items.size} elementi</i>)"

    { text: text, markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard) }
  end

  def self.show_private_keyboard(bot, chat_id, context)
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

  def self.markup_lista_globale(user_id, groups_and_topics, conf, page, total_pages, show_all, chat_id)
    item_buttons = []

    groups_and_topics.each do |row|
      g_id, t_id = row["gruppo_id"], row["topic_id"]
      is_active = (g_id == conf["db_id"].to_i && t_id == conf["topic_id"].to_i)
      info = DataManager.recupera_nomi_contesto(g_id, t_id)

      label = info[:nome] == "Privata" ? info[:topic] : (info[:topic] == "Generale" ? info[:nome] : "#{info[:nome]}: #{info[:topic]}")
      prefix = is_active ? "🎯 " : "📂 "

      # Tasto Contesto
      context_label = clamp_inline_text("#{prefix}#{label.upcase}")
      item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(text: context_label, callback_data: "mycontext:#{g_id}:#{t_id}:#{show_all ? 1 : 0}")]

      # Tasti Articoli
      DataManager.prendi_articoli_per_storico(g_id, t_id, user_id, show_all).each do |art|
        is_deleted = art["deleted"].to_i == 1
        is_unavailable = art["disponibile"].to_i == 0
        status = if is_deleted
          "↩️"
        elsif is_unavailable
          "❌"
        elsif art["comprato"] && !art["comprato"].empty?
          "✅"
        else
          "▫️"
        end
        tag = (show_all && g_id != 0) ? "[#{art["autore_init"] || "?"}] " : ""
        buyer_tag = status == "✅" ? " [#{art["buyer_init"] || "?"}]" : ""
        icona_foto = (art["ha_foto_reale"].to_i > 0) ? " 👁" : ""
        parsed = DataManager.parse_nome_categoria(art["nome"].to_s, art["categoria_id"], art["categoria_id"], g_id, t_id)
        nome_telegram = parsed[:nome].to_s.strip
        nome_telegram = art["nome"].to_s.strip if nome_telegram.empty?
        nome = safe_item_label(nome_telegram, 40)
        nome = "~~ #{nome} ~~" if is_deleted || is_unavailable

          row_text = "#{status} #{tag}#{icona_foto}#{nome}#{buyer_tag}"
        item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(
          text: clamp_inline_text(row_text),
          callback_data: "myallcomprato:#{art["id"]}:#{g_id}:#{t_id}:#{page}:#{show_all ? 1 : 0}",
        )]
      end
    end

    item_buttons << [Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "🧹 SUPERSCOPETTA (COMPRATI DA ME)",
      callback_data: "superscopetta:#{show_all ? 1 : 0}",
    )]

    # Navigazione
    nav = []
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "◀️", callback_data: "myitems_page:#{user_id}:#{page - 1}:#{show_all ? 1 : 0}") if page > 0
    nav << Telegram::Bot::Types::InlineKeyboardButton.new(text: "▶️", callback_data: "myitems_page:#{user_id}:#{page + 1}:#{show_all ? 1 : 0}") if page < total_pages - 1

    item_buttons << nav unless nav.empty?

    # Chiusura e Refresh
    item_buttons << [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "🔄", callback_data: "myitems_refresh:#{user_id}:#{page}:#{show_all ? 1 : 0}"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{chat_id}:0"),
    ]

    Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: item_buttons)
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
