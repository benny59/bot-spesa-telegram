require "cgi"
require "uri"
require_relative "ebsn_shop_client"

# Scheda prodotto della Farmacia Guacci (farmaciaguacci.it): medicinali e parafarmaci con codice AIC e foto della scatola.
# Legge i meta schema.org "itemprop" della pagina (il JSON-LD del sito non è JSON valido). Stessa forma di risposta degli
# altri negozi, così PWA e importazione non distinguono il negozio.
# Il codice AIC (`mpn`) non è un GTIN/EAN: gtin resta vuoto e l'AIC va in `aic`.
# I medicinali con obbligo di ricetta non hanno la foto sul sito: la pagina esiste ma `image_url` può mancare.
class GuacciClient
  HOST = "farmaciaguacci.it".freeze
  Error = EbsnShopClient::Error
  META = /<meta[^>]*itemprop="(name|image|mpn)"[^>]*content="([^"]*)"/
  AIC = /\A\d{9}\z/
  # Categoria suggerita: la PWA la preseleziona se la lista di destinazione ha una categoria con questo nome
  CATEGORIA = "(Para)farmacia".freeze
  # Entità con nome che CGI.unescapeHTML non conosce, ma che compaiono nei nomi dei medicinali
  ENTITA = {
    "reg" => "®", "trade" => "™", "agrave" => "à", "egrave" => "è", "eacute" => "é", "igrave" => "ì", "ograve" => "ò",
    "ugrave" => "ù", "deg" => "°", "nbsp" => " "
  }.freeze

  def self.supports?(url)
    !parse(url).nil?
  end

  def self.preview(url, connection: nil)
    slug = parse(url)
    raise Error, "Link negozio non supportato" unless slug

    pulito = "https://#{HOST}/#{slug}"
    http = connection || EbsnShopClient.connection_for("https://#{HOST}")
    response = EbsnShopClient.get(http, "/#{slug}")
    raise Error, "Prodotto Guacci non disponibile" unless response.success?

    normalize(response.body.to_s.dup.force_encoding(Encoding::UTF_8), url: pulito)
  rescue Faraday::Error => e
    raise Error, "Impossibile leggere il prodotto: #{e.message}"
  end

  def self.normalize(html, url: nil)
    meta = html.scan(META).each_with_object({}) { |(chiave, valore), dati| dati[chiave] ||= decodifica(valore) }
    aic = meta["mpn"].to_s
    raise Error, "Dati del prodotto non validi" unless aic.match?(AIC)

    name = titolo(meta["name"])
    raise Error, "Prodotto non trovato" if name.empty?

    {
      kind: "product",
      title: name.gsub("&", "e"),
      gtin: "",
      aic: aic,
      categoria: CATEGORIA,
      quantity: "",
      image_url: immagine(meta["image"]),
      source_url: url.to_s
    }
  end

  def self.fetch_image(url, connection: nil) = EbsnShopClient.download_image(url, hosts: [HOST], connection: connection)

  def self.image_host?(url)
    URI.parse(url.to_s.strip).host.to_s.downcase.delete_prefix("www.") == HOST
  rescue URI::InvalidURIError
    false
  end

  def self.decodifica(valore)
    CGI.unescapeHTML(valore.gsub(/&([a-z]+);/i) { ENTITA.fetch(Regexp.last_match(1).downcase, Regexp.last_match(0)) }).strip
  end

  # Il sito scrive il nome in maiuscolo ("TACHIPIRINA 500 mg 30 Compresse"): solo la prima parola, se tutta maiuscola, si abbassa
  def self.titolo(nome)
    nome.to_s.delete("®™").gsub(/\s+/, " ").strip.sub(/\A\p{Lu}{2,}(?=\s|\z)/) { |parola| parola.capitalize }
  end

  # Solo foto servite dal sito stesso, in https
  def self.immagine(url)
    image_host?(url) && url.to_s.start_with?("https://") ? url.to_s : nil
  end

  # => slug oppure nil: https://farmaciaguacci.it/<slug>, con o senza www; i parametri (_gl, gclid, ...) si ignorano
  def self.parse(url)
    uri = URI.parse(url.to_s.strip)
    return nil unless uri.scheme == "https" && uri.host.to_s.downcase.delete_prefix("www.") == HOST

    uri.path[%r{\A/([a-z0-9][a-z0-9-]*)/?\z}, 1]
  rescue URI::InvalidURIError
    nil
  end

  private_class_method :parse
end
