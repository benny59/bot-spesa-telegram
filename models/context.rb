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

  def self.enable_private_from_group(bot, context)
    set_private_for_group(context.user_id, context.gruppo_id)

    bot.api.send_message(
      chat_id: context.user_id,
      text: "🔒 Modalità privata attivata per il gruppo selezionato.\n" \
            "Da ora opererai in privato su questa lista.",
    )
  end

  def self.handle_private_set_callback(bot, callback, user_id, gruppo_id)
    set_private_for_group(user_id, gruppo_id)

    bot.api.answer_callback_query(callback_query_id: callback.id)

    bot.api.send_message(
      chat_id: user_id,
      text: "🔒 Modalità privata attivata.\n" \
            "Ora stai lavorando sul gruppo selezionato.",
    )
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
  # Cerchiamo se l'utente è in modalità privata
  row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{user_id}"])
  return unless row # Se non c'è config, siamo in modalità gruppo: NON notificare

  config = JSON.parse(row['value']) rescue nil
  return unless config && config["chat_id"]

  begin
    bot.api.send_message(
      chat_id: config["chat_id"],
      message_thread_id: (config["topic_id"].to_i == 0 ? nil : config["topic_id"]),
      text: messaggio,
      parse_mode: "Markdown"
    )
  rescue => e
    puts "❌ Errore notifica gruppo: #{e.message}"
  end
end


def self.show_group_selector(bot, user_id, message_id = nil)
  # 1. Recupero configurazione dal DB
  current_config = nil
  config_row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{user_id}"])
  current_config = JSON.parse(config_row['value']) rescue nil if config_row

 # Query che trova:
  # - I gruppi creati dall'utente
  # - I gruppi dove l'utente è stato visto (tramite la tabella items o altre interazioni)
  # - Includiamo tutti i topic censiti per quei gruppi
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

  # 2. Build della tastiera gruppi
  keyboard = rows.map do |row|
    is_active = current_config && 
                current_config['db_id'].to_i == row['id'].to_i && 
                current_config['topic_id'].to_i == row['topic_id'].to_i
    
    prefix = is_active ? "✅ " : "🏠 "
    t_label = row["t_nome"] || (row["topic_id"] == 0 ? "Generale" : "Topic #{row["topic_id"]}")
    
    [Telegram::Bot::Types::InlineKeyboardButton.new(
      text: "#{prefix}#{row["g_nome"]} (#{t_label})",
      callback_data: "private_set:#{row["id"]}:#{row["chat_id"]}:#{row["topic_id"]}"
    )]
  end

  # 3. Tasti di servizio con Check su Modalità Gruppo
  # Se current_config è nil, mettiamo il check qui
  group_mode_label = current_config.nil? ? "✅ Modalità Gruppo" : "👥 Modalità Gruppo"
  
  keyboard << [
    Telegram::Bot::Types::InlineKeyboardButton.new(text: group_mode_label, callback_data: "switch_to_group"),
    Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "ui_close:#{user_id}:0")
  ]

  markup = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: keyboard)
  text = "🔒 **Seleziona la lista specifica:**\n_(Il check ✅ indica la configurazione attiva)_"

  # 4. Aggiornamento o Invio
  if message_id
    begin
      bot.api.edit_message_reply_markup(
        chat_id: user_id, 
        message_id: message_id, 
        reply_markup: markup
      )
    rescue Telegram::Bot::Exceptions::ResponseError
      # Ignoriamo l'errore se la tastiera è identica
    end
  else
    bot.api.send_message(
      chat_id: user_id, 
      text: text, 
      reply_markup: markup, 
      parse_mode: "Markdown"
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
