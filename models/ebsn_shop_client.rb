require "faraday"
require "json"
require "uri"

# Schede prodotto dei negozi online costruiti sulla piattaforma EBSN (CoopShop, Tigros, NaturaSì, ...):
# stessa API pubblica /ebsn/api/products?slug=... Aggiungere un negozio = una riga in SHOPS.
class EbsnShopClient
  # path: cartella delle schede nel sito; brand e quantity: dove stanno marca e formato nella risposta
  DEFAULTS = { path: "product", brand: %w[shortDescr], quantity: %w[description] }.freeze
  SHOPS = {
    "www.coopshop.it" => { name: "CoopShop" },
    "www.tigros.it" => { name: "Tigros" },
    "www.naturasi.it" => { name: "NaturaSì", path: "prodotti", brand: %w[vendor name], quantity: %w[shortDescr] }
  }.transform_values { |shop| DEFAULTS.merge(shop).freeze }.freeze
  USER_AGENT = "BotSpesa/1.0"
  MAX_IMAGE_BYTES = 5 * 1024 * 1024
  OPEN_TIMEOUT = 8
  READ_TIMEOUT = 20
  ATTEMPTS = 2

  class Error < StandardError; end

  def self.supports?(url)
    !parse(url).nil?
  end

  def self.preview(url, connection: nil)
    host, slug = parse(url)
    raise Error, "Link negozio non supportato" unless host

    shop = SHOPS[host]
    http = connection || connection_for("https://#{host}")
    response = get(http, "/ebsn/api/products", slug: slug)
    raise Error, "Prodotto #{shop[:name]} non disponibile" unless response.success?

    normalize(JSON.parse(response.body), url: "https://#{host}/#{shop[:path]}/#{slug}")
  rescue Faraday::Error, JSON::ParserError => e
    raise Error, "Impossibile leggere il prodotto: #{e.message}"
  end

  def self.normalize(payload, url: nil)
    product = payload["data"]
    raise Error, "Dati del prodotto non validi" unless product.is_a?(Hash)

    name = product["name"].to_s.strip
    raise Error, "Prodotto non trovato" if name.empty?

    shop = SHOPS.fetch(host_of(url), DEFAULTS)
    brand, quantity = shop.values_at(:brand, :quantity).map { |keys| product.dig(*keys).to_s.strip }
    front = Array(product["media"]).find { |media| media["type"] == "front" } || Array(product["media"]).first

    {
      kind: "product",
      title: [name, brand].reject(&:empty?).join(" ").gsub("&", "e"),
      gtin: product["barcode"].to_s.strip,
      quantity: quantity,
      image_url: front && (front["medium"] || front["large"]),
      source_url: url.to_s
    }
  end

  # Scarica la foto solo dai negozi noti (l'URL arriva dal client: niente fetch arbitrari)
  def self.fetch_image(url, connection: nil) = download_image(url, hosts: SHOPS.keys, connection: connection)

  def self.image_host?(url) = SHOPS.key?(host_of(url))

  def self.host_of(url)
    URI.parse(url.to_s.strip).host.to_s.downcase
  rescue URI::InvalidURIError
    ""
  end

  # Scarico condiviso con gli altri negozi (ConadClient): https e solo gli host indicati
  def self.download_image(url, hosts:, connection: nil)
    uri = URI.parse(url.to_s.strip)
    host = uri.host.to_s.downcase
    raise Error, "Immagine non valida" unless uri.scheme == "https" && hosts.include?(host)

    http = connection || connection_for("https://#{host}")
    response = get(http, uri.request_uri)
    raise Error, "Immagine non disponibile" unless response.success?

    data = response.body.to_s.b
    raise Error, "Immagine non valida" if data.empty? || data.bytesize > MAX_IMAGE_BYTES

    data
  rescue URI::InvalidURIError, Faraday::Error => e
    raise Error, "Impossibile scaricare l'immagine: #{e.message}"
  end

  # => [host canonico, slug] oppure nil
  def self.parse(url)
    uri = URI.parse(url.to_s.strip)
    return nil unless uri.scheme == "https"

    host = "www.#{uri.host.to_s.downcase.delete_prefix('www.')}"
    shop = SHOPS[host]
    slug = shop && uri.path[%r{\A/(?:shop/)?#{shop[:path]}/([\w-]+)/?\z}, 1]
    slug ? [host, slug] : nil
  rescue URI::InvalidURIError
    nil
  end

  def self.connection_for(base_url)
    Faraday.new(url: base_url) do |client|
      client.options.open_timeout = OPEN_TIMEOUT
      client.options.timeout = READ_TIMEOUT
    end
  end

  # I negozi a volte rispondono lenti (o la rete del server è lenta): un solo nuovo tentativo sui timeout
  def self.get(http, path, params = nil)
    attempts = 0
    begin
      attempts += 1
      http.get(path, params) { |request| request.headers["User-Agent"] = USER_AGENT }
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed
      retry if attempts < ATTEMPTS
      raise
    end
  end

  private_class_method :parse, :host_of
end
