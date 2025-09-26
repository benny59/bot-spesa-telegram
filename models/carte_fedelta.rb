require 'sqlite3'
require 'barby'
require 'barby/barcode/code_128'
require 'barby/outputter/png_outputter'
require 'fileutils'
require 'faraday'
require_relative '../handlers/message_handler'

module CarteFedelta
  DATA_DIR = File.join(Dir.pwd, "data", "carte")

  FileUtils.mkdir_p(DATA_DIR)

  # Crea tabella se non esiste
  def self.setup_db
    DB.execute <<-SQL
      CREATE TABLE IF NOT EXISTS carte_fedelta (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        codice TEXT NOT NULL,
        immagine_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    SQL
  end

  # Aggiungi una nuova carta
  def self.add_card(bot, user_id, args)
    parts = args.split(" ", 2)
    if parts.size < 2
      bot.api.send_message(chat_id: user_id, text: "❌ Usa: /addcarta NOME CODICE")
      return
    end

    nome, codice = parts
    img_path = File.join(DATA_DIR, "card_#{user_id}_#{Time.now.to_i}.png")

    barcode = Barby::Code128B.new(codice)
    File.open(img_path, 'wb') { |f| f.write barcode.to_png(height: 80, margin: 5) }

    DB.execute("INSERT INTO carte_fedelta (user_id, nome, codice, immagine_path) VALUES (?, ?, ?, ?)",
               [user_id, nome, codice, img_path])

    bot.api.send_message(chat_id: user_id, text: "✅ Carta #{nome} aggiunta!")
  end

  # Mostra lista carte utente
  def self.show_user_cards(bot, user_id)
    carte = DB.execute("SELECT id, nome FROM carte_fedelta WHERE user_id = ?", [user_id])

    if carte.empty?
      bot.api.send_message(chat_id: user_id, text: "⚠️ Nessuna carta salvata.\nUsa /addcarta NOME CODICE per aggiungerne una.")
      return
    end

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(
      inline_keyboard: carte.map do |row|
        [Telegram::Bot::Types::InlineKeyboardButton.new(text: row['nome'], callback_data: "carte:#{user_id}:#{row['id']}")]
      end
    )

    bot.api.send_message(chat_id: user_id, text: "🎟️ Le tue carte:", reply_markup: keyboard)
  end

  # Callback gestione visualizzazione barcode
def self.handle_callback(bot, callback_query)
  user_id = callback_query.from.id
  data    = callback_query.data

  if data =~ /^carte:(\d+):(\d+)$/
    uid, carta_id = $1.to_i, $2.to_i

    # sicurezza: l’utente deve vedere solo le proprie carte
    return if uid != user_id

    row = DB.execute("SELECT * FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, uid]).first
    if row
      bot.api.send_photo(
        chat_id: user_id,
        photo: Faraday::UploadIO.new(row['immagine_path'], "image/png"),
        caption: "💳 #{row['nome']}"
      )
    else
      bot.api.send_message(chat_id: user_id, text: "❌ Carta non trovata.")
    end
  end
end
end
