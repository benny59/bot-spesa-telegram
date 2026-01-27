require "sqlite3"
require "rqrcode"
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

class CarteFedelta
  DATA_DIR = File.join(Dir.pwd, "data", "carte")
  FileUtils.mkdir_p(DATA_DIR)

  # Rimossa setup_db perché gestito da DataManager in db.rb

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

      # Usa DataManager con colonna 'tipo'
      DataManager.salva_nuova_carta(user_id, nome, codice, formato.to_s, result[:img_path])

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

  def self.show_user_cards(bot, user_id)
    # Usa DataManager
    carte = DataManager.prendi_carte_utente(user_id)

    if carte.empty?
      bot.api.send_message(chat_id: user_id, text: "⚠️ Nessuna carta salvata.\nUsa /addcarta NOME CODICE per aggiungerne una.")
      return
    end

    inline_keyboard = []
    current_row = []
    carte.each_with_index do |row, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(
        text: row["nome"],
        callback_data: "carte:#{user_id}:#{row["id"]}",
      )
      if current_row.size == 4 || index == carte.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end

    inline_keyboard << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "close_barcode")]
    keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard)
    bot.api.send_message(chat_id: user_id, text: "🎟️ Le tue carte:", reply_markup: keyboard)
  end

  def self.handle_callback(bot, callback_query)
    require_relative "../utils/logger" unless defined?(Logger)
    begin
      user_requesting = callback_query.from.id
      message_obj = callback_query.respond_to?(:message) ? callback_query.message : nil
      origin_chat = message_obj&.chat&.id
      origin_thread = message_obj&.message_thread_id || 0
      data = callback_query.data.to_s

      case data
      when /^carte:(\d+):(\d+)$/
        owner_id, carta_id = $1.to_i, $2.to_i
        allowed = false

        if owner_id == user_requesting
          allowed = true
        elsif origin_chat && origin_chat < 0
          gruppo_id = DB.get_first_value("SELECT id FROM gruppi WHERE chat_id = ?", [origin_chat])
          if gruppo_id
            link_exists = DB.get_first_value("SELECT 1 FROM gruppo_carte_collegamenti WHERE gruppo_id = ? AND carta_id = ? LIMIT 1", [gruppo_id, carta_id])
            allowed = !!link_exists
          end
        end

        unless allowed
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Non autorizzato")
          return
        end

        # Usa DataManager
        row = DataManager.prendi_dettaglio_carta(carta_id, owner_id)
        unless row
          bot.api.answer_callback_query(callback_query_id: callback_query.id, text: "❌ Carta non trovata")
          return
        end

        img_path = row["immagine_path"]
        if img_path.nil? || !File.exist?(img_path) || File.size(img_path) < 100
          # Nota: usiamo 'tipo' dalla riga DB
          result = genera_barcode_con_nome(row["codice"], row["nome"], owner_id, row["formato"])
          if result && result[:img_path]
            img_path = result[:img_path]
            DB.execute("UPDATE carte_fedelta SET immagine_path = ? WHERE id = ?", [img_path, carta_id])
          end
        end

        keyboard = Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: [[Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "close_barcode")]])
        dest_id = (origin_chat && origin_chat < 0) ? origin_chat : user_requesting

        bot.api.send_photo(
          chat_id: dest_id,
          message_thread_id: (origin_thread.to_i == 0 ? nil : origin_thread.to_i),
          photo: Faraday::UploadIO.new(img_path, "image/png"),
          caption: "💳 #{row["nome"]}\n🔢 #{row["codice"]}",
          parse_mode: "Markdown",
          reply_markup: keyboard,
        )
        bot.api.answer_callback_query(callback_query_id: callback_query.id)
      when "close_barcode"
        bot.api.delete_message(chat_id: message_obj.chat.id, message_id: message_obj.message_id) if message_obj
      end
    rescue => e
      Logger.error("ERRORE in CarteFedelta.handle_callback", error: e.message)
    end
  end

  def self.delete_card(bot, user_id, carta_id)
    # Recupero tramite DataManager
    carta = DataManager.prendi_dettaglio_carta(carta_id, user_id)
    unless carta
      bot.api.send_message(chat_id: user_id, text: "❌ Carta non trovata.")
      return false
    end

    DB.execute("DELETE FROM carte_fedelta WHERE id = ?", [carta_id])
    File.delete(carta["immagine_path"]) if carta["immagine_path"] && File.exist?(carta["immagine_path"])
    bot.api.send_message(chat_id: user_id, text: "✅ Carta '#{carta["nome"]}' eliminata.")
    true
  end

  def self.show_delete_interface(bot, user_id)
    user_cards = DataManager.prendi_carte_utente(user_id)
    if user_cards.empty?
      bot.api.send_message(chat_id: user_id, text: "⚠️ Non hai carte da eliminare.")
      return
    end

    inline_keyboard = []
    current_row = []
    user_cards.each_with_index do |card, index|
      current_row << Telegram::Bot::Types::InlineKeyboardButton.new(text: "🗑️ #{card["nome"]}", callback_data: "carte_confirm_delete:#{card["id"]}")
      if current_row.size == 3 || index == user_cards.size - 1
        inline_keyboard << current_row
        current_row = []
      end
    end
    inline_keyboard << [Telegram::Bot::Types::InlineKeyboardButton.new(text: "❌ Chiudi", callback_data: "carte_cancel_delete")]
    bot.api.send_message(chat_id: user_id, text: "Seleziona la carta da eliminare:", reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: inline_keyboard))
  end

  def self.add_card_from_photo(bot, user_id, nome, codice, image_path, formato_originale = nil)
    begin
      codice_da_salvare = codice.to_s.strip
      formato_final = formato_originale

      # Correzione specifica per UPC-A (12 cifre)
      if codice_da_salvare.length == 12
        puts " [RE-ENCODE] 🚨 Trasformo UPC-A in EAN-13 (aggiunta zero iniziale)"
        codice_da_salvare = "0" + codice_da_salvare
        formato_final = "ean13"
      end

      f_barby = formato_final ? mappa_formato_per_barby(formato_final) : identifica_formato(codice_da_salvare)

      # Generazione immagine
      result = genera_barcode_con_nome(codice_da_salvare, nome, user_id, f_barby)

      # Salvataggio nel database tramite DataManager (colonna 'formato')
      DataManager.salva_nuova_carta(user_id, nome, codice_da_salvare, result[:formato].to_s, result[:img_path])

      bot.api.send_photo(
        chat_id: user_id,
        photo: Faraday::UploadIO.new(result[:img_path], "image/png"),
        caption: "✅ Carta *#{nome}* creata!\n🔢 Codice: `#{codice_da_salvare}`\n📏 Formato: #{result[:formato]}",
        parse_mode: "Markdown",
      )
    rescue => e
      puts "❌ Errore: #{e.message}"
      bot.api.send_message(chat_id: user_id, text: "❌ Errore nella creazione: #{e.message}")
    end
  end
  # Logica privata di identificazione e generazione (invariata)
  private

  def self.identifica_formato(codice)
    codice_pulito = codice.to_s.gsub(/[^[:print:]]/, "").strip
    case codice_pulito
    when /^\d{8}$/ then :ean8
    when /^\d{12}$/ then :upca
    when /^\d{13}$/ then codice_pulito.start_with?("0") ? :upca : :ean13
    when /^\d{14}$/ then :itf14
    when /^\d{15,}$/ then :qrcode
    when /^[A-Z0-9\-\.\$\+\/\%\s]{4,20}$/ then :code39
    else :code128
    end
  end

  def self.genera_barcode_con_nome(codice, nome, user_id, formato_db = nil)
    nome_file = nome.downcase.gsub(/\s+/, "_")
    elimina_file_per_nome(user_id, nome_file)
    img_path = File.join(DATA_DIR, "#{nome_file}_#{user_id}_#{Time.now.to_i}.png")

    # IMPORTANTE: usiamo 'codice' che arriva come parametro
    formato = mappa_formato_per_barby(formato_db || identifica_formato(codice))

    begin
      case formato
      when :qrcode
        return genera_qrcode(codice, nome, img_path)
      when :ean13
        # Prende le prime 12 cifre per evitare errori di checksum invalidi
        barcode = Barby::EAN13.new(codice.to_s[0..11])
      when :upca
        # Se non è stato convertito, Barby UPC-A vuole 11 cifre e calcola la 12esima
        barcode = Barby::UPCA.new(codice.to_s[0..10])
      when :ean8
        barcode = Barby::EAN8.new(codice)
      when :code39
        barcode = Barby::Code39.new(codice)
      when :code25interleaved
        barcode = Barby::Code25Interleaved.new(codice)
      else
        barcode = Barby::Code128.new(codice)
      end

      png_data = barcode.to_png(height: 100, margin: 10, xdim: 2)
      File.open(img_path, "wb") { |f| f.write(png_data) }
      { success: true, img_path: img_path, formato: formato }
    rescue => e
      puts "🚨 Errore generazione #{formato}, uso fallback Code128: #{e.message}"
      barcode = Barby::Code128.new(codice)
      png_data = barcode.to_png(height: 100, margin: 10, xdim: 2)
      File.open(img_path, "wb") { |f| f.write(png_data) }
      { success: true, img_path: img_path, formato: :code128, provider: :fallback }
    end
  end

  def self.genera_qrcode(codice, nome, img_path)
    qrcode = RQRCode::QRCode.new(codice)
    png = qrcode.as_png(size: 300, border_modules: 4)
    File.open(img_path, "wb") { |f| f.write(png.to_s) }
    { success: true, img_path: img_path, formato: :qrcode }
  end

  def self.mappa_formato_per_barby(f)
    case f.to_s.downcase
    when "ean13", "ean_13" then :ean13
    when "upca", "upc_a" then :ean13 # Forza EAN13 per compatibilità UE
    when "qrcode", "qr_code" then :qrcode
    when "ean8", "ean_8" then :ean8
    when "code39" then :code39
    when "itf", "itf14", "code25interleaved" then :code25interleaved
    else f.to_sym rescue :code128
    end
  end

  def self.elimina_file_per_nome(user_id, nome_file)
    Dir.glob(File.join(DATA_DIR, "#{nome_file}_#{user_id}_*.png")).each { |f| File.delete(f) if File.exist?(f) }
  end
end
