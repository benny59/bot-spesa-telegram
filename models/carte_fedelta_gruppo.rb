# handlers/carte_fedelta_gruppo.rb
require_relative "./carte_fedelta"

class CarteFedeltaGruppo < CarteFedelta
  # Tabella specifica per le carte di gruppo
  TABLE_NAME = "group_cards"

  # Setup database per le carte gruppo
  def self.setup_db
    DB.execute <<-SQL
      CREATE TABLE IF NOT EXISTS #{TABLE_NAME} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gruppo_id INTEGER NOT NULL,
        user_id INTEGER NOT NULL,
        nome TEXT NOT NULL,
        codice TEXT NOT NULL,
        formato TEXT DEFAULT 'code128',
        immagine_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (gruppo_id) REFERENCES gruppi(id)
      );
    SQL
    aggiorna_schema_db_gruppo
  end

  # Aggiungi carta condivisa al gruppo
  def self.add_group_card(bot, chat_id, gruppo_id, user_id, args)
    parts = args.split(" ", 2)
    if parts.size < 2
      bot.api.send_message(chat_id: chat_id, text: "❌ Usa: /addcartagruppo NOME CODICE")  # 👈 chat_id
      return false
    end

    nome, codice = parts

    begin
      result = genera_barcode_con_nome(codice, nome, "gruppo_#{gruppo_id}")

      DB.execute(
        "INSERT INTO #{TABLE_NAME} (gruppo_id, user_id, nome, codice, formato, immagine_path) VALUES (?, ?, ?, ?, ?, ?)",
        [gruppo_id, user_id, nome, codice, result[:formato].to_s, result[:img_path]]
      )

      if File.exist?(result[:img_path])
        bot.api.send_photo(
          chat_id: chat_id,  # 👈 ORA IN GRUPPO
          photo: Faraday::UploadIO.new(result[:img_path], "image/png"),
          caption: "✅ Carta #{nome} aggiunta al gruppo! (Formato: #{result[:formato]})",
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "✅ Carta #{nome} aggiunta al gruppo! (ma immagine non generata)")  # 👈 chat_id
      end
      return true
    rescue => e
      puts "❌ Errore aggiunta carta gruppo: #{e.message}"
      bot.api.send_message(chat_id: chat_id, text: "❌ Errore nell'aggiunta della carta al gruppo: #{e.message}")  # 👈 chat_id
      return false
    end
  end

  def self.show_user_shared_cards_report(bot, user_id)
    # Trova tutte le carte condivise dall'utente in tutti i gruppi
    carte_condivise = DB.execute("
    SELECT gc.*, g.nome as gruppo_nome 
    FROM #{TABLE_NAME} gc 
    JOIN gruppi g ON gc.gruppo_id = g.id 
    WHERE gc.user_id = ? 
    ORDER BY g.nome, LOWER(gc.nome) ASC",
                                 [user_id])

    if carte_condivise.empty?
      bot.api.send_message(
        chat_id: user_id,
        text: "📊 Non hai condiviso carte in nessun gruppo.\nUsa /addcartagruppo nei gruppi per condividere le tue carte.",
      )
      return
    end

    # Raggruppa per gruppo
    carte_per_gruppo = carte_condivise.group_by { |c| c["gruppo_nome"] }

    # Costruisci il report
    report = "📊 *Le tue carte condivise per gruppo:*\n\n"

    carte_per_gruppo.each do |gruppo_nome, carte|
      report += "🏢 *#{gruppo_nome}*\n"
      carte.each do |carta|
        report += "  • #{carta["nome"]} (ID: #{carta["id"]})\n"
      end
      report += "\n"
    end

    report += "ℹ️ Per eliminare una carta, usa /delcartagruppo ID nel gruppo corrispondente."

    bot.api.send_message(
      chat_id: user_id,
      text: report,
      parse_mode: "Markdown",
    )
  end

  # Mostra carte del gruppo
  def self.show_group_cards(bot, gruppo_id, chat_id, user_id)
    # chat_id è l'ID del gruppo, non dell'utente
    carte = DB.execute("
    SELECT gc.id, gc.nome, gc.user_id, u.full_name 
    FROM #{TABLE_NAME} gc 
    LEFT JOIN whitelist u ON gc.user_id = u.user_id 
    WHERE gc.gruppo_id = ? 
    ORDER BY LOWER(gc.nome) ASC",
                       [gruppo_id])

    if carte.empty?
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Nessuna carta condivisa nel gruppo.\nUsa /addcartagruppo NOME CODICE per aggiungerne una.")
      return
    end

    # Crea bottoni organizzati in colonne (4 colonne)
    inline_keyboard = []
    current_row = []

    carte.each_with_index do |row, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: row["nome"],
        callback_data: "carte_gruppo:#{gruppo_id}:#{row["id"]}",
      )

      if current_row.size == 4 || index == carte.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    info_carte = carte.map { |c| "• #{c["nome"]} (da #{c["full_name"] || "Utente"})" }.join("\n")

    bot.api.send_message(
      chat_id: chat_id,  # 👈 INVIA NEL GRUPPO
      text: "🏢 Carte condivise del gruppo:\n#{info_carte}",
      reply_markup: keyboard,
    )
  end

  def self.handle_delcartagruppo(bot, msg, chat_id, user_id, gruppo)
    return unless gruppo

    # 👇 PULISCI IL TESTO RIMUOVENDO TUTTO DOPO /delcartagruppo
    text = msg.text.to_s
    # Rimuovi il comando e qualsiasi mention del bot
    text = text.gsub(/\/delcartagruppo(@\w+)?/, "").strip

    if text.empty?
      # Mostra il sottomenu
      show_delete_interface(bot, gruppo["id"], user_id, chat_id)
    else
      # Eliminazione diretta con ID
      carta_id = text.to_i
      if carta_id > 0
        delete_group_card(bot, gruppo["id"], user_id, carta_id)
      else
        # Se non è un ID numerico, cerca per nome
        carte = DB.execute("SELECT id, nome FROM #{TABLE_NAME} WHERE gruppo_id = ? AND user_id = ? AND LOWER(nome) = LOWER(?)",
                           [gruppo["id"], user_id, text.strip])
        if carte.any?
          show_delete_interface(bot, gruppo["id"], user_id)
        else
          bot.api.send_message(
            chat_id: chat_id,
            text: "❌ Nessuna carta trovata con nome '#{text}'. Usa /delcartagruppo senza parametri per vedere le tue carte.",
          )
        end
      end
    end
  end  # Elimina carta del gruppo (solo chi l'ha aggiunta)

  def self.delete_group_card(bot, gruppo_id, user_id, carta_id, chat_id = nil)
    # chat_id è ora opzionale - se non fornito, usa user_id (chat privata)
    carta = DB.execute("SELECT * FROM #{TABLE_NAME} WHERE id = ? AND gruppo_id = ?", [carta_id, gruppo_id]).first

    unless carta
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "❌ Carta non trovata.")
      return false
    end

    if carta["user_id"] != user_id
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "❌ Puoi eliminare solo le carte che hai aggiunto tu.")
      return false
    end

    DB.execute("DELETE FROM #{TABLE_NAME} WHERE id = ?", [carta_id])

    # Cancella anche l'immagine se esiste
    if carta["immagine_path"] && File.exist?(carta["immagine_path"])
      File.delete(carta["immagine_path"])
    end

    target_chat = chat_id || user_id
    bot.api.send_message(chat_id: target_chat, text: "✅ Carta '#{carta["nome"]}' eliminata dal gruppo.")
    return true
  end

  # Mostra interfaccia per eliminare le proprie carte
  def self.show_delete_interface(bot, gruppo_id, user_id, chat_id = nil)
    user_cards = DB.execute("SELECT id, nome FROM #{TABLE_NAME} WHERE gruppo_id = ? AND user_id = ? ORDER BY LOWER(nome) ASC", [gruppo_id, user_id])

    if user_cards.empty?
      target_chat = chat_id || user_id
      bot.api.send_message(chat_id: target_chat, text: "⚠️ Non hai carte da eliminare nel gruppo.")
      return
    end

    inline_keyboard = user_cards.map do |card|
      [Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🗑️ #{card["nome"]}",
        callback_data: "carte_gruppo_confirm_delete:#{gruppo_id}:#{card["id"]}",
      )]
    end

    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🔙 Indietro",
        callback_data: "carte_gruppo_back:#{gruppo_id}",
      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    # 👇 INVIA NEL GRUPPO SE chat_id È FORNITO, ALTRIMENTI IN PRIVATO
    target_chat = chat_id || user_id
    bot.api.send_message(
      chat_id: target_chat,
      text: "Seleziona la carta da eliminare:",
      reply_markup: keyboard,
    )
  end

  # Callback handling per carte gruppo
  def self.handle_callback(bot, callback_query)
    user_id = callback_query.from.id
    chat_id = callback_query.message.chat.id  # 👈 Prendi la chat dove è arrivato il comando
    data = callback_query.data

    case data
    when /^carte_gruppo:(\d+):(\d+)$/
      gruppo_id, carta_id = $1.to_i, $2.to_i
      mostra_carta_gruppo(bot, chat_id, gruppo_id, carta_id)  # 👈 chat_id invece di user_id
    when /^carte_gruppo_delete:(\d+):(\d+)$/
      gruppo_id, uid = $1.to_i, $2.to_i
      return if uid != user_id
      show_delete_interface(bot, gruppo_id, user_id, chat_id)  # 👈 PASSARE chat_id
    when /^carte_gruppo_confirm_delete:(\d+):(\d+)$/
      gruppo_id, carta_id = $1.to_i, $2.to_i
      delete_group_card(bot, gruppo_id, user_id, carta_id, chat_id)

      # Ricarica l'interfaccia principale NEL GRUPPO
      show_group_cards(bot, gruppo_id, chat_id, user_id)  # 👈 chat_id invece di user_id
    when /^carte_gruppo_back:(\d+)$/
      gruppo_id = $1.to_i
      show_group_cards(bot, gruppo_id, chat_id, user_id)  # 👈 chat_id invece di user_id
    end
  end

  # E aggiorna anche show_delete_interface per lavorare in privato
  def self.mostra_carta_gruppo(bot, chat_id, gruppo_id, carta_id)
    # chat_id è l'ID del gruppo
    row = DB.execute("SELECT * FROM #{TABLE_NAME} WHERE id = ? AND gruppo_id = ?", [carta_id, gruppo_id]).first

    if row
      img_path = row["immagine_path"]

      # Rigenera se necessario
      unless img_path && File.exist?(img_path) && File.size(img_path) > 100
        begin
          result = genera_barcode_con_nome(row["codice"], row["nome"], "gruppo_#{gruppo_id}")
          DB.execute("UPDATE #{TABLE_NAME} SET immagine_path = ?, formato = ? WHERE id = ?",
                     [result[:img_path], result[:formato].to_s, carta_id])
          img_path = result[:img_path]
        rescue => e
          puts "❌ Rigenerazione carta gruppo fallita: #{e.message}"
          bot.api.send_message(chat_id: chat_id, text: "❌ Errore nella rigenerazione del barcode.")
          return
        end
      end

      if File.exist?(img_path)
        caption = "🏢 Carta Condivisa\n💳 #{row["nome"]}\n🔢 Codice: #{row["codice"]}"

        bot.api.send_photo(
          chat_id: chat_id,  # 👈 INVIA NEL GRUPPO
          photo: Faraday::UploadIO.new(img_path, "image/png"),
          caption: caption,
        )
      else
        bot.api.send_message(chat_id: chat_id, text: "❌ Immagine non disponibile per #{row["nome"]}")
      end
    else
      bot.api.send_message(chat_id: chat_id, text: "❌ Carta non trovata nel gruppo.")
    end
  end

  private

  def self.aggiorna_schema_db_gruppo
    # Verifica se la colonna 'formato' esiste
    columns = DB.execute("PRAGMA table_info(#{TABLE_NAME})")
    formato_exists = columns.any? { |col| col["name"] == "formato" }

    unless formato_exists
      puts "🔄 [DB] Aggiungo colonna 'formato' alla tabella group_cards..."
      DB.execute("ALTER TABLE #{TABLE_NAME} ADD COLUMN formato TEXT DEFAULT 'code128'")
      puts "✅ [DB] Colonna 'formato' aggiunta a group_cards"
    end

    # Aggiorna i record esistenti con un formato predefinito
    DB.execute("UPDATE #{TABLE_NAME} SET formato = 'code128' WHERE formato IS NULL")
  end
end
