# frozen_string_literal: true

require "json"
require "prawn"
require "tempfile"
require "fileutils"
require "faraday"
require_relative "../db"
require_relative "photo_album"
require_relative "../models/lista"

# Comando /pdf: lista della spesa in formato B5, pensata per un amico a cui
# affidare la spesa (stampata o letta sul telefono). Per ogni articolo ancora
# da comprare: riquadro da barrare a matita, miniatura (se c'è) a sinistra,
# nome e note. Raggruppata per categoria.
module ListaPdf
  PAGINA = "B5" # 176 x 250 mm
  MARGINE = 28
  QUADRATO = 15       # riquadro per la matita
  MINIATURA = 52      # lato massimo della foto
  GAP = 9
  RIGA_MIN = 28
  FONT_CANDIDATI = [
    ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    ["/system/fonts/Roboto-Regular.ttf", "/system/fonts/Roboto-Bold.ttf"],
    ["/system/fonts/NotoSans-Regular.ttf", "/system/fonts/NotoSans-Bold.ttf"],
    ["/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans.ttf", "/data/data/com.termux/files/usr/share/fonts/TTF/DejaVuSans-Bold.ttf"],
  ].freeze
  CACHE_FOTO = File.expand_path("../data/foto_cache", __dir__)
  GRIGIO = "777777"
  COLORE_LINK = "1A4FA0"
  LINEA = "CCCCCC"

  # Genera il PDF e ritorna il percorso del file temporaneo (nil se nulla da comprare).
  # user_id serve per la lista personale (gruppo 0): ognuno vede solo i propri articoli.
  def self.genera(bot, g_id, t_id, user_id: nil)
    items = articoli_da_comprare(g_id, t_id, user_id: user_id)
    return nil if items.empty?

    info = DataManager.recupera_nomi_contesto(g_id.to_i, t_id.to_i)
    sezioni = raggruppa(items, g_id, t_id)
    path = File.join(Dir.tmpdir, "lista_spesa_#{Time.now.to_i}.pdf")
    tmp_foto = []
    campi = []

    Prawn::Document.generate(path, page_size: PAGINA, margin: MARGINE, info: { Title: "Lista della spesa", Creator: "Bot Spesa" }) do |pdf|
      imposta_font(pdf)
      intestazione(pdf, info, items.size)

      sezioni.each do |categoria, articoli|
        pdf.start_new_page if pdf.cursor < 70
        titolo_categoria(pdf, categoria)
        articoli.each do |art|
          foto = prima_foto(bot, art, tmp_foto)
          riga_articolo(pdf, art, foto, campi)
        end
      end

      numera_pagine(pdf)
      registra_form(pdf, campi)
    end
    path
  ensure
    tmp_foto&.each { |f| File.delete(f) if File.exist?(f) }
  end

  # Articoli ancora da comprare, con gruppo/topic valorizzati (usata anche dalla lista HTML).
  def self.articoli_da_comprare(g_id, t_id, user_id: nil)
    tutti = if g_id.to_i == 0 && user_id.to_i != 0
        Lista.personale(user_id.to_i)
      else
        DataManager.prendi_articoli_ordinati(g_id, t_id)
      end
    items = tutti.select { |i| i["deleted"].to_i == 0 && i["comprato"].to_s.strip.empty? }
    items.each { |i| i["gruppo_id"] ||= g_id; i["topic_id"] ||= t_id }
    items
  end

  # ---------------------------------------------------------------------------
  def self.raggruppa(items, g_id, t_id)
    gruppi = items.group_by { |i| i["categoria_nome"].to_s.strip }
    ordine = gruppi.keys.sort_by { |k| [k.empty? ? 1 : 0, k.downcase] }
    ordine.map { |k| [k, gruppi[k]] }
  end

  def self.imposta_font(pdf)
    coppia = FONT_CANDIDATI.find { |r, b| File.exist?(r) && File.exist?(b) }
    if coppia
      pdf.font_families.update("Spesa" => { normal: coppia[0], bold: coppia[1], italic: coppia[0], bold_italic: coppia[1] })
      pdf.font "Spesa"
      @unicode = true
    else
      pdf.font "Helvetica"
      @unicode = false
    end
  end

  # Senza TTF il font standard copre solo Windows-1252: tolgo il resto.
  def self.pulisci(testo)
    s = testo.to_s.gsub(/[\u0000-\u001F]/, " ").strip
    s = s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    # emoji e simboli non presenti nei font
    s = s.gsub(/[\u{1F000}-\u{1FFFF}\u{2190}-\u{2BFF}\u{FE0F}\u{200D}]/, "").strip
    s = s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "").encode("UTF-8") unless @unicode
    s
  end

  def self.intestazione(pdf, info, totale)
    pdf.fill_color "000000"
    pdf.text pulisci("Lista della spesa"), size: 20, style: :bold
    sotto = [info[:nome], (info[:topic].to_s.empty? || info[:topic] == "Generale" || info[:topic] == "Lista Personale") ? nil : info[:topic]].compact.join(" · ")
    pdf.fill_color GRIGIO
    pdf.text pulisci(sotto), size: 11 unless sotto.empty?
    pdf.text "#{Time.now.strftime('%d/%m/%Y')}  ·  #{totale} #{totale == 1 ? 'articolo' : 'articoli'}", size: 9
    pdf.fill_color "000000"
    pdf.move_down 6
    pdf.stroke_color "000000"
    pdf.line_width 1.2
    pdf.stroke_horizontal_rule
    pdf.move_down 10
  end

  def self.titolo_categoria(pdf, categoria)
    nome = categoria.empty? ? "Altro" : categoria
    pdf.move_down 6
    pdf.fill_color "333333"
    pdf.text pulisci(nome).upcase, size: 9, style: :bold, character_spacing: 1
    pdf.fill_color "000000"
    pdf.stroke_color LINEA
    pdf.line_width 0.6
    pdf.stroke_horizontal_rule
    pdf.move_down 5
  end

  def self.riga_articolo(pdf, art, foto, campi)
    nome = pulisci(PhotoAlbum.nome_pulito(art, art["gruppo_id"], art["topic_id"]))
    img_w = img_h = 0
    if foto
      begin
        w, h = dimensioni(foto)
        scala = [MINIATURA.to_f / w, MINIATURA.to_f / h].min
        img_w = (w * scala).round
        img_h = (h * scala).round
      rescue => e
        puts "⚠️ [LISTA_PDF] foto illeggibile: #{e.message}"
        foto = nil
      end
    end

    x_nome = QUADRATO + GAP + MINIATURA + GAP
    altezza = [RIGA_MIN, img_h + 8].max
    pdf.start_new_page if pdf.cursor < altezza + 4
    top = pdf.cursor

    # riquadro per la matita, centrato in verticale sulla riga
    pdf.stroke_color "000000"
    pdf.line_width 1
    y_quadrato = top - (altezza - QUADRATO) / 2.0
    pdf.stroke_rectangle [0, y_quadrato], QUADRATO, QUADRATO
    aggiungi_spunta(pdf, art["id"], [0, y_quadrato], campi)

    if foto
      pdf.image foto, at: [QUADRATO + GAP + (MINIATURA - img_w) / 2, top - (altezza - img_h) / 2.0], width: img_w, height: img_h
    end

    link = link_articolo(art)
    pdf.fill_color(link ? COLORE_LINK : "000000")
    pdf.bounding_box([x_nome, top], width: pdf.bounds.width - x_nome, height: altezza) do
      pdf.text_box nome, at: [0, altezza], width: pdf.bounds.width, height: altezza, size: 12, style: :bold,
                         valign: :center, overflow: :shrink_to_fit, min_font_size: 8
    end

    if link
      # clic su nome e miniatura: apre la scheda prodotto nel browser
      sx = pdf.bounds.absolute_left + QUADRATO + GAP
      dx = pdf.bounds.absolute_right
      basso = pdf.bounds.absolute_bottom + top - altezza
      alto = pdf.bounds.absolute_bottom + top
      pdf.link_annotation([sx, basso, dx, alto], Border: [0, 0, 0], A: { Type: :Action, S: :URI, URI: link })
    end
    pdf.fill_color "000000"

    pdf.move_cursor_to top - altezza
    pdf.stroke_color "E3E3E3"
    pdf.line_width 0.4
    pdf.stroke_horizontal_line x_nome, pdf.bounds.width
    pdf.move_down 3
  end

  # --- Form PDF: una casella cliccabile (AcroForm) sopra ogni riquadro -------
  # Il riquadro disegnato resta (si stampa e si spunta a matita); in un lettore
  # PDF con moduli la casella si tocca e compare la spunta.
  def self.aggiungi_spunta(pdf, item_id, punto, campi)
    @ap ||= {}
    @ap[pdf.object_id] ||= {
      on: ap_stream(pdf, "q 1.8 w 0 0 0 RG #{QUADRATO * 0.2} #{QUADRATO * 0.5} m #{QUADRATO * 0.42} #{QUADRATO * 0.2} l #{QUADRATO * 0.82} #{QUADRATO * 0.82} l S Q"),
      off: ap_stream(pdf, "q Q"),
    }
    ap = @ap[pdf.object_id]
    x = pdf.bounds.absolute_left + punto[0]
    y = pdf.bounds.absolute_bottom + punto[1]
    widget = pdf.ref!(
      Type: :Annot, Subtype: :Widget, FT: :Btn,
      T: "art_#{item_id}", TU: "Preso",
      Rect: [x, y - QUADRATO, x + QUADRATO, y],
      F: 4, V: :Off, AS: :Off,
      MK: { CA: PDF::Core::ByteString.new("4") },
      DA: PDF::Core::ByteString.new("/ZaDb 0 Tf 0 g"),
      Ff: 0,
      AP: { N: { Yes: ap[:on], Off: ap[:off] } },
      P: pdf.page.dictionary,
    )
    pdf.page.dictionary.data[:Annots] ||= []
    pdf.page.dictionary.data[:Annots] << widget
    campi << widget
  end

  def self.ap_stream(pdf, contenuto)
    ref = pdf.ref!(Type: :XObject, Subtype: :Form, BBox: [0, 0, QUADRATO, QUADRATO], Resources: {})
    ref << contenuto
    ref
  end

  def self.registra_form(pdf, campi)
    return if campi.empty?
    zadb = pdf.ref!(Type: :Font, Subtype: :Type1, BaseFont: :ZapfDingbats)
    pdf.state.store.root.data[:AcroForm] = pdf.ref!(
      Fields: campi,
      NeedAppearances: false,
      DA: PDF::Core::ByteString.new("/ZaDb 0 Tf 0 g"),
      DR: { Font: { ZaDb: zadb } },
    )
    @ap&.delete(pdf.object_id)
  end

  # Scheda di approfondimento: il link salvato sull'articolo (Yuka, negozio); se manca,
  # la pagina Open Food Facts del suo barcode (come il tasto "i" delle app).
  def self.link_articolo(art)
    diretto = link_valido(art["link_url"])
    return diretto if diretto

    gtin = art["gtin"].to_s.strip
    return nil unless gtin.match?(/\A\d{8,14}\z/)
    meta = DB.get_first_value("SELECT metadata_json FROM prodotti WHERE gtin = ?", [gtin])
    sorgente = (JSON.parse(meta.to_s)["source_url"] rescue nil)
    link_valido(sorgente) || link_valido("https://world.openfoodfacts.org/product/#{gtin}")
  end

  # Solo http/https: niente schemi strani dentro un PDF che l'amico apre sul telefono.
  def self.link_valido(url)
    u = url.to_s.strip
    return nil unless u.match?(%r{\Ahttps?://[^\s]+\z}i)
    # URI in ASCII puro (richiesto dalla specifica PDF): il resto in %XX, e ByteString
    # perché Prawn non la converta in UTF-16 come fa con le stringhe di testo.
    PDF::Core::ByteString.new(u.b.gsub(/[^\x21-\x7e]/n) { |c| format("%%%02X", c.ord) })
  end

  def self.dimensioni(path)
    File.open(path, "rb") do |f|
      obj = Prawn::Images::JPG.new(f.read)
      [obj.width, obj.height]
    end
  rescue
    [MINIATURA, MINIATURA]
  end

  def self.numera_pagine(pdf)
    n = pdf.page_count
    return if n < 1
    pdf.number_pages "<page> / <total>", at: [pdf.bounds.right - 60, -14], width: 60, align: :right, size: 8, color: GRIGIO
  end

  # ---------------------------------------------------------------------------
  # Foto: cache locale, altrimenti scarico da Telegram; ridimensiono se possibile.
  def self.prima_foto(bot, art, tmp, **opz)
    f = DataManager.prendi_foto_articolo(art["id"]).first
    return nil unless f
    grezzo = file_foto(bot, f)
    return nil unless grezzo
    ridotta = riduci(grezzo, **opz)
    tmp << ridotta if ridotta != grezzo && !tmp.include?(ridotta)
    ridotta
  rescue => e
    puts "⚠️ [LISTA_PDF] foto articolo #{art['id']}: #{e.message}"
    nil
  end

  def self.file_foto(bot, f)
    cache = File.join(CACHE_FOTO, "#{f['file_unique_id']}.jpg")
    return cache if File.exist?(cache)
    return nil if f["file_id"].to_s.start_with?("local:") || bot.nil?

    info = bot.api.get_file(file_id: f["file_id"])
    url = "https://api.telegram.org/file/bot#{bot.api.token}/#{info.file_path}"
    FileUtils.mkdir_p(CACHE_FOTO)
    File.binwrite(cache, Faraday.get(url).body)
    cache
  end

  # Le foto caricate dall'app possono pesare >1 MB: se c'è ImageMagick le riduco,
  # così il PDF resta leggero da inoltrare.
  def self.riduci(path, lato: 400, qualita: 75, soglia: 120_000)
    return path if File.size(path) < soglia
    tool = %w[magick convert].find { |t| system("which #{t} > /dev/null 2>&1") }
    return path unless tool
    out = Tempfile.new(["miniatura", ".jpg"]).path
    ok = system(tool, path, "-auto-orient", "-resize", "#{lato}x#{lato}>", "-quality", qualita.to_s, "-strip", out)
    ok && File.size?(out) ? out : path
  end
end
