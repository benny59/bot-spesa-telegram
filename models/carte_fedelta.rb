require "sqlite3"
require "rqrcode"  # AGGIUNGI QUESTA RIGA IN ALTO
require "barby"
require "barby/barcode/code_128"
require "barby/barcode/ean_13"
require "barby/barcode/ean_8"
require "barby/barcode/code_39"
require "barby/barcode/code_25_interleaved"

require "barby/outputter/png_outputter"

require_relative "barcode_scanner"

require "fileutils"
require "faraday"
#require_relative '../handlers/message_handler'

class CarteFedelta
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
        formato TEXT DEFAULT 'code128',
        immagine_path TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      );
    SQL
    aggiorna_schema_db
  end

  # Aggiungi una nuova carta
  def self.add_card(bot, user_id, args)
    parts = args.split(" ", 2)
    if parts.size < 2
      bot.api.send_message(chat_id: user_id, text: "❌ Usa: /addcarta NOME CODICE")
      return
    end

    nome, codice = parts

    begin
      formato = identifica_formato(codice)
      result = genera_barcode_con_nome(codice, nome, user_id, formato)

      DB.execute(
        "INSERT INTO carte_fedelta (user_id, nome, codice, formato, immagine_path) VALUES (?, ?, ?, ?, ?)",
        [user_id, nome, codice, formato.to_s, result[:img_path]] # 🔥 AGGIUNTO formato.to_s
      )

      if File.exist?(result[:img_path])
        bot.api.send_photo(
          chat_id: user_id,
          photo: Faraday::UploadIO.new(result[:img_path], "image/png"),
          caption: "✅ Carta #{nome} aggiunta! (Formato: #{result[:formato]})",
        )
      else
        bot.api.send_message(chat_id: user_id, text: "✅ Carta #{nome} aggiunta! (ma immagine non generata)")
      end
    rescue => e
      puts "❌ Errore: #{e.message}"
      bot.api.send_message(chat_id: user_id, text: "❌ Errore nella generazione della carta: #{e.message}")
    end
  end

  # Mostra lista carte utente
  def self.show_user_cards(bot, user_id)
    carte = DB.execute("SELECT id, nome FROM carte_fedelta WHERE user_id = ? ORDER BY LOWER(nome) ASC", [user_id])

    if carte.empty?
      bot.api.send_message(chat_id: user_id, text: "⚠️ Nessuna carta salvata.\nUsa /addcarta NOME CODICE per aggiungerne una.")
      return
    end

    # Crea bottoni organizzati in colonne (4 colonne)
    inline_keyboard = []
    current_row = []

    carte.each_with_index do |row, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: row["nome"],
        callback_data: "carte:#{user_id}:#{row["id"]}",
      )

      # Ogni 4 bottoni, vai a nuova riga
      if current_row.size == 4 || index == carte.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    # 🔴 AGGIUNTO: Riga con tasto "Chiudi"
    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        #        callback_data: "checklist_close:#{user_id}",
        callback_data: "close_barcode",  # Cambiato da "checklist_close:#{user_id}"

      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)
    bot.api.send_message(chat_id: user_id, text: "🎟️ Le tue carte:", reply_markup: keyboard)
  end

  # Callback gestione visualizzazione barcode
# inserisci questo metodo in models/carte_fedelta.rb al posto dell'esistente `handle_callback`
def self.handle_callback(bot, callback_query)
  require_relative "../utils/logger" unless defined?(Logger)
  Logger.debug("CarteFedelta.handle_callback entry", data: callback_query.data, from: callback_query.from.id)

  begin
    aggiorna_schema_db

    user_requesting = callback_query.from.id
    message_obj = callback_query.respond_to?(:message) ? callback_query.message : nil
    origin_chat = message_obj&.chat&.id
    origin_thread = message_obj&.message_thread_id || 0
    data = callback_query.data.to_s

    Logger.debug("handle_callback parsed", user_requesting: user_requesting, origin_chat: origin_chat, origin_thread: origin_thread, data: data)

    case data
    when /^carte:(\d+):(\d+)$/
      owner_id = $1.to_i
      carta_id = $2.to_i

      # Permessi: permetti la visualizzazione se:
      # - chi clicca è il proprietario, oppure
      # - la carta è collegata al gruppo della chat di origine (se l'origine è una chat di gruppo)
      allowed = false

      if owner_id == user_requesting
        allowed = true
      elsif origin_chat && origin_chat < 0
        # è una chat di gruppo: verifichiamo che esista il collegamento
        gruppo_id = DB.get_first_value("SELECT id FROM gruppi WHERE chat_id = ?", [origin_chat])
        if gruppo_id
          link_exists = DB.get_first_value("SELECT 1 FROM gruppo_carte_collegamenti WHERE gruppo_id = ? AND carta_id = ? LIMIT 1", [gruppo_id, carta_id])
          allowed = !!link_exists
          Logger.debug("controllo link gruppo-carta", gruppo_id: gruppo_id, carta_id: carta_id, link_exists: !!link_exists)
        end
      end

      unless allowed
        Logger.warn("Accesso non autorizzato a carta", requested_owner: owner_id, by: user_requesting, origin_chat: origin_chat)
        begin
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Non autorizzato")
        rescue => _
        end
        return
      end

      row = DB.get_first_row("SELECT * FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, owner_id])
      unless row
        Logger.warn("Carta non trovata", carta_id: carta_id, owner: owner_id)
        bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Carta non trovata")
        return
      end

      Logger.info("Mostro carta", card: row["nome"], carta_id: carta_id, owner: owner_id, dest_chat: origin_chat, dest_thread: origin_thread)

      img_path = row["immagine_path"]
      if img_path.nil? || !File.exist?(img_path) || File.size(img_path) < 100
        Logger.debug("Immagine mancante o corrotta; rigenero", carta_id: carta_id, codice: row["codice"])
        begin
          result = genera_barcode_con_nome(row["codice"], row["nome"], owner_id, row["formato"])
          if result && result[:img_path]
            img_path = result[:img_path]
            DB.execute("UPDATE carte_fedelta SET immagine_path = ? WHERE id = ?", [img_path, carta_id])
            Logger.debug("Rigenerata immagine", path: img_path)
          end
        rescue => e
          Logger.error("Errore rigenerazione barcode", error: e.message)
        end
      end

      # Costruisci tastiera di chiusura
      inline_keyboard = [
        [
          Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "close_barcode"),
        ],
      ]
      keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

      if img_path && File.exist?(img_path)
        begin
          # Invia nel contesto di origine: se origin_chat è nil => manda in DM al richiedente
          if origin_chat && origin_chat < 0
            # invio nel gruppo/thread di origine
            bot.api.send_photo(
              chat_id: origin_chat,
              message_thread_id: (origin_thread.to_i == 0 ? nil : origin_thread.to_i),
              photo: Faraday::UploadIO.new(img_path, "image/png"),
              caption: "💳 #{row['nome']}\n🔢 #{row['codice']}",
              parse_mode: "Markdown",
              reply_markup: keyboard
            )
          else
            # invia in DM al richiedente (o al proprietario se richiesto)
            bot.api.send_photo(
              chat_id: user_requesting,
              photo: Faraday::UploadIO.new(img_path, "image/png"),
              caption: "💳 #{row['nome']}\n🔢 #{row['codice']}",
              parse_mode: "Markdown",
              reply_markup: keyboard
            )
          end

          bot.api.answer_callback_query(callback_query_id: callback_query.id)
          Logger.info("Foto inviata", dest: (origin_chat || user_requesting), path: img_path)
        rescue => e
          Logger.error("Errore invio foto", error: e.message)
          begin
            bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Errore invio immagine")
          rescue => _
          end
        end
      else
        Logger.warn("Immagine non disponibile per carta", carta_id: carta_id)
        bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Immagine non disponibile")
      end

    when "close_barcode"
      Logger.debug("close_barcode ricevuto", from: callback_query.from.id)
      begin
        if message_obj
          bot.api.delete_message(chat_id: message_obj.chat.id, message_id: message_obj.message_id)
        else
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "✅ Chiuso")
        end
      rescue Telegram::Bot::Exceptions::ResponseError => e
        Logger.warn("delete_message fallito in close_barcode", error: e.message)
        begin
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "✅ Chiuso")
        rescue => _
        end
      rescue => e
        Logger.error("Errore generico close_barcode", error: e.message)
        begin
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "✅ Chiuso")
        rescue => _
        end
      end

    else
      Logger.warn("Callback CarteFedelta non gestita", data: data)
      begin
        bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "Operazione non riconosciuta")
      rescue => _
      end
    end

  rescue => e
    Logger.error("ERRORE in CarteFedelta.handle_callback", error: e.message)
    Logger.error(e.backtrace.first(5))
    begin
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Errore interno")
    rescue => _
    end
  end
end
 # METODI PRIVATI
  private

  def self.scan_and_save_card(bot, user_id, image_path, card_name = nil)
    barcode_data = BarcodeScanner.scan_image(image_path)

    return { success: false, error: "Nessun barcode rilevato" } unless barcode_data

    # Se non abbiamo il nome, restituiamo i dati per il naming
    unless card_name
      return {
               success: true,
               barcode_data: barcode_data,
               needs_naming: true,
             }
    end

    # Se abbiamo il nome, salviamo direttamente
    begin
      DB.execute(
        "INSERT INTO carte_fedelta (user_id, nome, codice, formato) VALUES (?, ?, ?, ?)",
        [user_id, card_name, barcode_data, "code128"]
      )

      return {
               success: true,
               barcode_data: barcode_data,
               card_name: card_name,
             }
    rescue => e
      return { success: false, error: e.message }
    end
  end

  def self.identifica_formato(codice)
    codice_originale = codice.to_s
    codice_pulito = codice_originale.gsub(/[^[:print:]]/, "").strip

    puts "🔍 [BARCODE] Identificando formato per: '#{codice_pulito}' (lunghezza: #{codice_pulito.length})"

    case codice_pulito
    when /^\d{8}$/
      puts "✅ Identificato come EAN8"
      :ean8
    when /^\d{12}$/
      puts "✅ Identificato come UPCA"
      :upca
    when /^\d{13}$/
      if codice_pulito.start_with?("0")
        puts "✅ Identificato come UPCA (EAN13 con 0)"
        :upca
      else
        puts "✅ Identificato come EAN13"
        :ean13
      end
    when /^\d{14}$/
      puts "✅ Identificato come ITF14"
      :itf14
    when /^\d{15,}$/
      puts "✅ Identificato come QRCODE (lunghezza > 14)"
      :qrcode
    when /^\d{6,}$/
      if codice_pulito.length.even? && codice_pulito.length >= 6
        puts "✅ Identificato come ITF"
        :itf
      else
        puts "🔄 Identificato come CODE128 (fallback numerico)"
        :code128
      end
    when /^[A-Z0-9\-\.\$\+\/\%\s]{4,20}$/ # Pattern tipico CODE_39
      puts "✅ Identificato come CODE39"
      :code39
    when /^[A-Za-z0-9+\-*\/@#$%&\s]{1,20}$/
      puts "✅ Identificato come CODE128 (alfanumerico)"
      :code128
    else
      puts "🔄 Identificato come CODE128 (fallback generale)"
      :code128
    end
  end

  def self.genera_barcode_con_nome(codice, nome, user_id, formato_db = nil)
    nome_file = nome.downcase.gsub(/\s+/, "_")
    elimina_file_per_nome(user_id, nome_file)
    img_path = File.join(DATA_DIR, "#{nome_file}_#{user_id}_#{Time.now.to_i}.png")

    formatox = formato_db || identifica_formato(codice)
    formato = mappa_formato_per_barby(formatox)
    puts "🔍 [BARCODE] Generando #{formato} per: #{nome} - #{codice}"

    begin
      case formato
      when :code25interleaved
        barcode = Barby::Code25Interleaved.new(codice)
      when :code39
        barcode = Barby::Code39.new(codice)
      when :ean8
        barcode = Barby::EAN8.new(codice)
      when :upca
        barcode = Barby::EAN13.new(codice)
      when :ean13
        if codice.length == 13
          puts "🔍 [EAN-13] Codice pulito: #{codice} -> #{codice[0..11]}"
          barcode = Barby::EAN13.new(codice[0..11])
        else
          barcode = Barby::EAN13.new(codice)
        end
      when :code128
        barcode = Barby::Code128.new(codice)
      when :qrcode
        return genera_qrcode(codice, nome, img_path)
      else
        barcode = Barby::Code128.new(codice)
      end

      # Genera con Barby
      png_data = barcode.to_png(height: 100, margin: 10, xdim: 2)
      File.open(img_path, "wb") { |f| f.write(png_data) }
      puts "✅ [BARBY] #{formato.to_s.upcase} generato: #{img_path}"
      return { success: true, img_path: img_path, formato: formato, provider: :barby }
    rescue => e
      puts "❌ [BARBY] Errore generazione #{formato}: #{e.message}"

      # 🔥 SOLO PER ITF USA STROKES COME FALLBACK
      if formato == :code25interleaved || formato == :itf
        begin
          puts "🔄 [STROKES FALLBACK] Tentativo con Strokes per ITF..."
          barcode = Strokes::Barcode.new(:itf, codice)
          barcode.save(img_path, height: 100, margin: 10)
          puts "✅ [STROKES] ITF generato: #{img_path}"
          return { success: true, img_path: img_path, formato: :itf, provider: :strokes_fallback }
        rescue => e2
          puts "❌ [STROKES] Errore: #{e2.message}"
        end
      end

      # FALLBACK FINALE A CODE-128
      begin
        puts "🔄 [FALLBACK] Tentativo con Code128..."
        barcode = Barby::Code128.new(codice)
        png_data = barcode.to_png(height: 100, margin: 10, xdim: 2)
        File.open(img_path, "wb") { |f| f.write(png_data) }
        puts "✅ [CODE128] Barcode generato: #{img_path}"
        return { success: true, img_path: img_path, formato: :code128, provider: :fallback }
      rescue => e3
        puts "❌ [CODE128] Errore: #{e3.message}"
        return { success: false, error: e3.message }
      end
    end
  end

  # 👇 AGGIUNGI QUESTO NUOVO METODO PER GENERARE QR CODE
  def self.genera_qrcode(codice, nome, img_path)
    puts "📱 [QRCODE] Generando QR code per: #{nome}"

    begin
      qrcode = RQRCode::QRCode.new(codice)

      png = qrcode.as_png(
        bit_depth: 1,
        border_modules: 4,
        color_mode: ChunkyPNG::COLOR_GRAYSCALE,
        color: "black",
        file: nil,
        fill: "white",
        module_px_size: 6,
        resize_exactly_to: false,
        resize_gte_to: false,
        size: 300,
      )

      File.open(img_path, "wb") { |f| f.write(png.to_s) }
      puts "✅ [QRCODE] QR code generato: #{img_path}"

      return { success: true, img_path: img_path, formato: :qrcode, provider: :rqrcode }
    rescue => e
      puts "❌ [QRCODE] Errore generazione QR: #{e.message}"
      # Fallback a Code128
      barcode = Barby::Code128.new(codice)
      png_data = barcode.to_png(height: 250, margin: 25, xdim: 4)
      File.open(img_path, "wb") { |f| f.write(png_data) }

      return { success: false, img_path: img_path, formato: :code128, provider: :fallback, error: e.message }
    end
  end
  def self.genera_barcode_con_tec_it(codice, formato)
    formato_tec_it = caso_formato_tec_it(formato)
    url = "https://barcode.tec-it.com/barcode.ashx?data=#{URI.encode_www_form_component(codice)}&code=#{formato_tec_it}&dpi=150&unit=Pixel&height=100"

    puts "🔍 [TEC-IT] Richiedo barcode ingrandito: #{formato_tec_it} per #{codice}"

    begin
      response = Faraday.get(url)
      if response.status == 200 && response.body.size > 1000
        puts "✅ [TEC-IT] Barcode ingrandito generato (#{response.body.size} bytes)"
        return response.body
      else
        raise "Risposta non valida dal servizio TEC-IT"
      end
    rescue => e
      puts "❌ [TEC-IT] Errore: #{e.message}"
      raise e
    end
  end

  def self.caso_formato_tec_it(formato)
    case formato
    when :upca then "UPCA"
    when :ean13 then "EAN13"
    when :ean8 then "EAN8"
    when :itf14, :itf then "ITF"
    else "Code128"
    end
  end

  def self.elimina_file_per_nome(user_id, nome_file)
    pattern = File.join(DATA_DIR, "#{nome_file}_#{user_id}_*.png")
    files = Dir.glob(pattern)
    files.each do |file|
      File.delete(file) if File.exist?(file)
      puts "🗑️ File eliminato: #{file}"
    end
    puts "🔍 Cercato pattern: #{pattern}, trovati: #{files.size} file"
  end

  def self.aggiorna_schema_db
    # Verifica se la colonna 'formato' esiste
    columns = DB.execute("PRAGMA table_info(carte_fedelta)")
    formato_exists = columns.any? { |col| col["name"] == "formato" }

    unless formato_exists
      puts "🔄 [DB] Aggiungo colonna 'formato' alla tabella..."
      DB.execute("ALTER TABLE carte_fedelta ADD COLUMN formato TEXT DEFAULT 'code128'")
      puts "✅ [DB] Colonna 'formato' aggiunta"
    end

    # Aggiorna i record esistenti con un formato predefinito
    DB.execute("UPDATE carte_fedelta SET formato = 'code128' WHERE formato IS NULL")
  end

  def self.delete_card(bot, user_id, carta_id)
    carta = DB.execute("SELECT * FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, user_id]).first

    unless carta
      bot.api.send_message(chat_id: user_id, text: "❌ Carta non trovata.")
      return false
    end

    DB.execute("DELETE FROM carte_fedelta WHERE id = ?", [carta_id])

    # Cancella anche l'immagine se esiste
    if carta["immagine_path"] && File.exist?(carta["immagine_path"])
      File.delete(carta["immagine_path"])
    end

    bot.api.send_message(chat_id: user_id, text: "✅ Carta '#{carta["nome"]}' eliminata.")
    return true
  end

  # handlers/carte_fedelta.rb

  def self.show_delete_interface(bot, user_id)
    user_cards = DB.execute("SELECT id, nome FROM carte_fedelta WHERE user_id = ? ORDER BY LOWER(nome) ASC", [user_id])

    if user_cards.empty?
      bot.api.send_message(chat_id: user_id, text: "⚠️ Non hai carte da eliminare.")
      return
    end

    inline_keyboard = []
    current_row = []

    user_cards.each_with_index do |card, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "🗑️ #{card["nome"]}",
        callback_data: "carte_confirm_delete:#{card["id"]}",
      )

      # 🔥 MODIFICA: 3 carte per riga invece di 1
      if current_row.size == 3 || index == user_cards.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    # Bottone "Indietro" (manteniamo "Indietro" qui invece di "Chiudi" per coerenza)
    inline_keyboard << [
      Telegram::Bot::Types::InlineKeyboardButton.new(
        text: "❌ Chiudi",
        callback_data: "carte_cancel_delete",  # Cambiato da "carte_back"
      ),
    ]

    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)

    bot.api.send_message(
      chat_id: user_id,
      text: "Seleziona la carta da eliminare:",
      reply_markup: keyboard,
    )
  end

  # handlers/carte_fedelta.rb

  def self.add_card_from_photo(bot, user_id, nome, codice, image_path, formato_originale = nil)
    begin
      if formato_originale
        puts "🔍 [BARCODE] Usando formato originale: #{formato_originale}"

        # 🔥 CORREZIONE: Mappa i formati non standard ai formati Barby supportati
        formato = mappa_formato_per_barby(formato_originale)
        puts "🔍 [BARCODE] Formato mappato per Barby: #{formato}"
      else
        formato = identifica_formato(codice)
        puts "🔍 [BARCODE] Formato identificato: #{formato}"
      end

      result = genera_barcode_con_nome(codice, nome, "user_#{user_id}", formato)

      # Salva la carta nel database
      DB.execute(
        "INSERT INTO carte_fedelta (user_id, nome, codice, formato, immagine_path) VALUES (?, ?, ?, ?, ?)",
        [user_id, nome, codice, formato.to_s, result[:img_path]]
      )

      if File.exist?(result[:img_path])
        bot.api.send_photo(
          chat_id: user_id,
          photo: Faraday::UploadIO.new(result[:img_path], "image/png"),
          caption: "✅ Carta *#{nome}* creata con successo!\nCodice: `#{codice}`\nFormato: #{result[:formato]}",
          parse_mode: "Markdown",
        )
      else
        bot.api.send_message(
          chat_id: user_id,
          text: "✅ Carta *#{nome}* creata con successo!\nCodice: `#{codice}`\nFormato: #{result[:formato]}",
          parse_mode: "Markdown",
        )
      end
    rescue => e
      puts "❌ Errore creazione carta da foto: #{e.message}"
      bot.api.send_message(chat_id: user_id, text: "❌ Errore nella creazione della carta: #{e.message}")
    end
  end

  def self.mappa_formato_per_barby(formato_db)
    case formato_db.to_s.downcase
    when "code25interleaved", "itf", "interleaved2of5", "itf14"
      :code25interleaved  # 🔥 USA IL NOME CORRETTO DI BARBY
    when "code39"
      :code39
    when "ean8"
      :ean8
    when "ean13", "ean_13"
      :ean13
    when "upca", "upc_a"
      :upca
    when "code128"
      :code128
    when "qrcode", "qr_code"
      :qrcode
    else
      puts "⚠️ Formato non riconosciuto '#{formato_db}', uso code128 come fallback"
      :code128
    end
  end
end
