# models/context.rb
class Context
  attr_reader :chat_id, :topic_id, :user_id, :scope

  def initialize(chat_id:, user_id:, topic_id: 0, scope: :group)
    @chat_id = chat_id
    @user_id = user_id
    @topic_id = topic_id || 0
    @scope = scope.to_sym
  end

  def self.from_callback(callback)
    chat = callback.message.chat

    scope = if chat.type == "private"
        "private"
      else
        "group"
      end

    new(
      chat_id: chat.id,
      topic_id: callback.message.message_thread_id || 0,
      user_id: callback.from.id,
      scope: scope,
    )
  end

  def self.set_private_for_group(user_id, gruppo_id, topic_id = 0)
    value = {
      scope: "private",
      gruppo_id: gruppo_id,
      topic_id: topic_id,
    }.to_json

    DB.execute(
      "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
      ["context:#{user_id}", value]
    )
  end

  def self.activate_private_for_group(bot, msg, gruppo)
    user_id = msg.from.id
    chat_id = msg.chat.id
    t_id = msg.message_thread_id || 0

    # Log di sicurezza per il debug interno
    puts "🛠️ [Context] Eseguo attivazione: User #{user_id}, Group DB ID #{gruppo["id"]}, Topic #{t_id}"

    # 1. Recupero nome topic (gestione fallback)
    topic_name = DB.get_first_value(
      "SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?",
      [chat_id, t_id]
    ) || (t_id == 0 ? "Generale" : "Topic #{t_id}")

    # 2. Salvataggio della configurazione nel DB
    config_json = {
      db_id: gruppo["id"],
      chat_id: chat_id,
      topic_id: t_id,
      topic_name: topic_name,
    }.to_json

    begin
      DB.execute(
        "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
        ["context:#{user_id}", config_json]
      )
      puts "✅ Config salvata per context:#{user_id}"

      # 3. Risposta nel GRUPPO (nel topic corretto)
      # usa t_id calcolato sopra e passa nil se = 0
      thread_id = (t_id.to_i > 0) ? t_id.to_i : nil

      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: thread_id,
        text: "📲 <b>#{msg.from.first_name}</b>, ora puoi gestire la lista <i>#{gruppo["nome"]} (#{topic_name})</i> in privato!",
        parse_mode: "HTML",
      )
      # 4. Messaggio in PRIVATO all'utente
      bot.api.send_message(
        chat_id: user_id,
        text: "🕹️ <b>Modalità Privata Attiva</b>\nTarget: <code>#{gruppo["nome"]} (#{topic_name})</code>\n\nPuoi usare i comandi qui sotto:",
        parse_mode: "HTML",
      )

      # 5. Mostra il selettore (così vede il check verde sul gruppo appena attivato)
      self.show_group_selector(bot, user_id)
    rescue => e
      puts "❌ ERRORE in activate_private_for_group: #{e.message}"
      puts e.backtrace.first(3) # Mostra le prime 3 righe dell'errore per capire dove crasha
    end
  end

  # --- modalità ---
  def group_chat?
    @scope == :group
  end

  def private_chat?
    @scope == :private
  end

  # --- switch esplicito ---
  def self.activate_private(bot, context, gruppo_id: nil)
    if gruppo_id
      set_private_context(context.user_id, gruppo_id)
      notify_private_activated(bot, context.user_id, gruppo_id)
    else
      show_group_selector(bot, context.user_id)
    end
  end

  # ========================================
  # Mostra elenco gruppi in privato
  # ========================================
  # models/context.rb

  def self.notifica_gruppo_se_privato(bot, user_id, messaggio)
    puts "sono in notifica gruppo"

    # 1. Controllo manuale nel DB (chiave globale)
    config_val = DB.get_first_value("SELECT value FROM config WHERE key = 'verbose'")
    is_verbose = ["on", "true", "1"].include?(config_val.to_s.downcase)

    # 2. Se verbose è false, usciamo subito e non inviamo nulla
    return unless is_verbose

    # Cerchiamo se l'utente è in modalità privata
    row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{user_id}"])
    return unless row # Se non c'è config, siamo in modalità gruppo: NON notificare

    config = JSON.parse(row["value"]) rescue nil
    return unless config && config["chat_id"]

    begin
      bot.api.send_message(
        chat_id: config["chat_id"],
        message_thread_id: (config["topic_id"].to_i == 0 ? nil : config["topic_id"]),
        text: messaggio,
        parse_mode: "Markdown",
      )
    rescue => e
      puts "❌ Errore notifica gruppo: #{e.message}"
    end
  end

def self.show_group_selector(bot, user_id, message_id = nil)
    # 1. Recupero configurazione dal DB
    current_config = nil
    config_row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{user_id}"])
    current_config = JSON.parse(config_row["value"]) rescue nil if config_row

    # Query che trova i gruppi e i topic relativi
    query = <<-SQL
    SELECT DISTINCT g.id, g.chat_id, g.nome as g_nome, 
           COALESCE(t.topic_id, 0) as topic_id,
           COALESCE(t.nome, CASE WHEN t.topic_id = 0 OR t.topic_id IS NULL THEN 'Generale' ELSE 'Topic ' || t.topic_id END) as t_nome
    FROM gruppi g
    LEFT JOIN topics t ON g.chat_id = t.chat_id
    WHERE g.id IN (
      SELECT gruppo_id FROM items WHERE creato_da = ?
      UNION
      SELECT id FROM gruppi WHERE creato_da = ?
    )
    ORDER BY g.nome ASC, topic_id ASC
  SQL

    rows = DB.execute(query, [user_id, user_id])

    return bot.api.send_message(chat_id: user_id, text: "❌ Nessuna lista attiva.") if rows.empty?

    # 2. Build della tastiera gruppi con distinzione icone
    keyboard = rows.map do |row|
      is_active = current_config &&
                  current_config["db_id"].to_i == row["id"].to_i &&
                  current_config["topic_id"].to_i == row["topic_id"].to_i

      # MODIFICA SOLO ICONA: 👥 per Supergruppo (-100), 🏠 per Gruppo Legacy
      icona_tipo = row["chat_id"].to_s.start_with?("-100") ? "👥 " : "🏠 "
      prefix = is_active ? "✅ #{icona_tipo}" : icona_tipo

      t_label = row["t_nome"] || (row["topic_id"] == 0 ? "Generale" : "Topic #{row["topic_id"]}")

      [Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "#{prefix}#{row["g_nome"]} (#{t_label})",
        callback_data: "private_set:#{row["id"]}:#{row["chat_id"]}:#{row["topic_id"]}",
      )]
    end

    # 3. Tasti di servizio con Check su Modalità Gruppo
    group_mode_label = current_config.nil? ? "✅ Modalità Gruppo" : "💬 Modalità Gruppo"

    keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(text: group_mode_label, callback_data: "switch_to_group"),
      Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{user_id}:0"),
    ]

    markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
    text = "🔒 **Seleziona la lista specifica:**\n_(Il check ✅ indica la configurazione attiva)_"

    # 4. Aggiornamento o Invio
    if message_id
      begin
        bot.api.edit_message_reply_markup(
          chat_id: user_id,
          message_id: message_id,
          reply_markup: markup,
        )
      rescue Telegram::Bot::Exceptions::ResponseError
        # Ignoriamo l'errore se la tastiera è identica
      end
    else
      bot.api.send_message(
        chat_id: user_id,
        text: text,
        reply_markup: markup,
        parse_mode: "Markdown",
      )
    end
  end
  # ========================================
  # Feedback all’utente
  # ========================================
  def self.notify_private_activated(bot, user_id, gruppo_id)
    gruppo = DB.get_first_row(
      "SELECT nome FROM gruppi WHERE id = ?",
      [gruppo_id]
    )

    bot.api.send_message(
      chat_id: user_id,
      text: "🔒 Modalità privata attiva sul gruppo:\n<b>#{gruppo["nome"]}</b>",
      parse_mode: "HTML",
    )
  end

  def to_private!
    @scope = :private
  end

  def to_group!
    @scope = :group
  end

  # Factory MINIMA: nessuna logica applicativa
  def self.from_message(msg)
    chat_id = msg.chat.id
    topic_id = msg.respond_to?(:message_thread_id) ? (msg.message_thread_id || 0) : 0
    user_id = msg.from.id
    scope = if msg.chat.type == "private"
        "private"
      else
        "group"
      end
    puts "#{chat_id} #{user_id} #{topic_id}"
    new(
      chat_id: chat_id,
      topic_id: topic_id,
      user_id: user_id,
      scope: scope,
    )
  end
end
