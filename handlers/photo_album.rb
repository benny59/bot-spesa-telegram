# frozen_string_literal: true

require "json"
require "cgi"
require_relative "../db"

# Tasto 📸 Foto: invia le foto della lista come album (sendMediaGroup, max 10 per
# album) invece di un messaggio per foto. Di default solo gli articoli non ancora
# comprati; il messaggio di controllo permette di aggiungere i comprati e di
# chiudere tutto (album + controllo), lasciando la chat come prima del click.
module PhotoAlbum
  MAX_PER_ALBUM = 10

  # Apre l'album per (chat, thread). Un eventuale album già aperto sullo stesso
  # thread viene chiuso prima, così un nuovo click non accumula messaggi.
  # Ritorna :vuoto se non c'è nessuna foto in lista, altrimenti l'id dell'album.
  def self.apri(bot, chat_id, g_id, t_id, tutti: false)
    thread_id = chat_id.to_i > 0 ? 0 : t_id.to_i
    thread_param = thread_id > 0 ? thread_id : nil

    articoli = DataManager.prendi_articoli_ordinati(g_id, t_id).select { |i| i["ha_foto"].to_i > 0 && i["deleted"].to_i == 0 }
    return :vuoto if articoli.empty?

    da_comprare = articoli.reject { |i| comprato?(i) }
    comprati = articoli.select { |i| comprato?(i) }
    mostrati = tutti ? da_comprare + comprati : da_comprare

    chiudi_aperti(bot, chat_id, thread_id)
    DB.execute("DELETE FROM photo_albums WHERE creato_il < datetime('now', '-7 days')")
    DB.execute(
      "INSERT INTO photo_albums (chat_id, thread_id, gruppo_id, topic_id, tutti) VALUES (?, ?, ?, ?, ?)",
      [chat_id.to_i, thread_id, g_id.to_i, t_id.to_i, tutti ? 1 : 0]
    )
    album_id = DB.get_first_value("SELECT last_insert_rowid()").to_i

    foto = mostrati.flat_map { |art| foto_con_didascalia(art, g_id, t_id) }
    inviati = []
    foto.each_slice(MAX_PER_ALBUM) do |gruppo|
      inviati.concat(invia_gruppo(bot, chat_id, thread_param, gruppo))
    end

    testo = if mostrati.empty?
        "📸 Nessuna foto tra gli articoli da comprare."
      elsif tutti
        "📸 #{mostrati.size} articoli con foto (compresi i già comprati)."
      else
        "📸 #{mostrati.size} articoli da comprare con foto."
      end

    righe = []
    if tutti && da_comprare.any?
      righe << [btn("⬅️ Solo da comprare", "photo_switch:#{album_id}:0")]
    elsif !tutti && comprati.any?
      righe << [btn("👁 Anche già comprati (#{comprati.size})", "photo_switch:#{album_id}:1")]
    end
    righe << [btn("🗑️ Chiudi", "photo_close:#{album_id}")]

    ctrl = bot.api.send_message(
      chat_id: chat_id,
      text: testo,
      message_thread_id: thread_param,
      reply_markup: Telegram::Bot::Types::InlineKeyboardMarkup.new(inline_keyboard: righe),
    )
    inviati << ctrl.message_id if ctrl.respond_to?(:message_id)

    DB.execute("UPDATE photo_albums SET message_ids = ? WHERE id = ?", [inviati.to_json, album_id])
    album_id
  end

  # Cancella tutti i messaggi dell'album (foto + controllo).
  def self.chiudi(bot, chat_id, album_id)
    row = DB.get_first_row("SELECT * FROM photo_albums WHERE id = ? AND chat_id = ?", [album_id.to_i, chat_id.to_i])
    return false unless row
    cancella_messaggi(bot, chat_id, row["message_ids"])
    DB.execute("DELETE FROM photo_albums WHERE id = ?", [album_id.to_i])
    true
  end

  # Cambia modalità (solo da comprare <-> anche comprati): chiude e riapre.
  def self.cambia(bot, chat_id, album_id, tutti)
    row = DB.get_first_row("SELECT * FROM photo_albums WHERE id = ? AND chat_id = ?", [album_id.to_i, chat_id.to_i])
    return nil unless row
    apri(bot, chat_id, row["gruppo_id"], row["topic_id"], tutti: tutti)
  end

  # ---------------------------------------------------------------------------
  def self.comprato?(item)
    !item["comprato"].to_s.strip.empty?
  end

  def self.btn(text, data)
    Telegram::Bot::Types::InlineKeyboardButton.new(text: text, callback_data: data)
  end

  def self.chiudi_aperti(bot, chat_id, thread_id)
    DB.execute("SELECT * FROM photo_albums WHERE chat_id = ? AND thread_id = ?", [chat_id.to_i, thread_id.to_i]).each do |row|
      cancella_messaggi(bot, chat_id, row["message_ids"])
      DB.execute("DELETE FROM photo_albums WHERE id = ?", [row["id"]])
    end
  end

  def self.cancella_messaggi(bot, chat_id, json_ids)
    ids = (JSON.parse(json_ids.to_s) rescue [])
    ids.each do |mid|
      begin
        bot.api.delete_message(chat_id: chat_id, message_id: mid)
      rescue => e
        puts "⚠️ [PHOTO_ALBUM] delete #{mid}: #{e.message}" unless e.message.to_s.include?("not found")
      end
    end
  end

  def self.nome_pulito(art, g_id, t_id)
    parsed = DataManager.parse_nome_categoria(art["nome"].to_s, art["categoria_id"], art["categoria_id"], g_id, t_id)
    n = parsed[:nome].to_s.strip
    n = art["nome"].to_s.strip if n.empty?
    n
  end

  # [{ file_id:, file_unique_id:, item_id:, caption: }]
  def self.foto_con_didascalia(art, g_id, t_id)
    nome = CGI.escapeHTML(nome_pulito(art, g_id, t_id))
    fotos = DataManager.prendi_foto_articolo(art["id"])
    fotos.each_with_index.map do |f, idx|
      cap = fotos.size > 1 ? "<b>#{nome}</b> (#{idx + 1}/#{fotos.size})" : "<b>#{nome}</b>"
      { file_id: f["file_id"], file_unique_id: f["file_unique_id"], item_id: art["id"], caption: cap[0, 1024] }
    end
  end

  # Invia fino a 10 foto: album se >= 2, foto singola altrimenti.
  # Ritorna gli id dei messaggi inviati.
  def self.invia_gruppo(bot, chat_id, thread_param, gruppo)
    media = []
    extra = {}
    validi = []
    gruppo.each_with_index do |f, i|
      ref = f[:file_id].to_s
      if ref.start_with?("local:")
        path = File.join(__dir__, "..", "data", "foto_cache", "#{f[:file_unique_id]}.jpg")
        unless File.exist?(path)
          puts "❌ Foto locale non trovata: #{path}"
          next
        end
        key = "file#{i}"
        extra[key] = Faraday::UploadIO.new(path, "image/jpeg")
        ref = "attach://#{key}"
      end
      media << { type: "photo", media: ref, caption: f[:caption], parse_mode: "HTML" }
      validi << f
    end
    return [] if media.empty?

    if media.size == 1
      foto = extra.values.first || media.first[:media]
      sent = bot.api.send_photo(chat_id: chat_id, photo: foto, caption: media.first[:caption],
                                parse_mode: "HTML", message_thread_id: thread_param)
      aggiorna_file_id_locali(validi, [sent])
      [sent.message_id]
    else
      sent = bot.api.send_media_group(chat_id: chat_id, media: media, message_thread_id: thread_param, **extra.transform_keys(&:to_sym))
      sent = Array(sent)
      aggiorna_file_id_locali(validi, sent)
      sent.map(&:message_id)
    end
  rescue => e
    puts "❌ [PHOTO_ALBUM] Errore invio foto: #{e.message}"
    []
  end

  # Le foto "local:" caricate da disco ricevono il file_id Telegram: lo salviamo.
  def self.aggiorna_file_id_locali(validi, messaggi)
    validi.each_with_index do |f, i|
      next unless f[:file_id].to_s.start_with?("local:")
      tg = messaggi[i]&.photo&.last
      next unless tg
      DB.execute(
        "UPDATE item_images SET file_id = ?, file_unique_id = ? WHERE item_id = ? AND file_id = ?",
        [tg.file_id, tg.file_unique_id, f[:item_id], f[:file_id]]
      )
    end
  end
end
