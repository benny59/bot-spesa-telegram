require "faraday"
require "json"
require "uri"

# Schede prodotto dei negozi online costruiti sulla piattaforma EBSN (CoopShop, Tigros, ...):
# stessa API pubblica /ebsn/api/products?slug=..., stessi campi. Aggiungere un negozio = una riga in SHOPS.
class EbsnShopClient
  SHOPS = {
    "www.coopshop.it" => "CoopShop",
    "www.tigros.it" => "Tigros"
  }.freeze
  USER_AGENT = "BotSpesa/1.0"
  MAX_IMAGE_BYTES = 5 * 1024 * 1024

  class Error < StandardError; end

  def self.supports?(url)
    !parse(url).nil?
  end

  def self.preview(url, connection: nil)
    host, slug = parse(url)
    raise Error, "Link negozio non supportato" unless host

    http = connection || connection_for("https://#{host}")
    response = http.get("/ebsn/api/products", slug: slug) { |request| request.headers["User-Agent"] = USER_AGENT }
    raise Error, "Prodotto #{SHOPS[host]} non disponibile" unless response.success?

    normalize(JSON.parse(response.body), url: "https://#{host}/product/#{slug}")
  rescue Faraday::Error, JSON::ParserError => e
    raise Error, "Impossibile leggere il prodotto: #{e.message}"
  end

  def self.normalize(payload, url: nil)
    product = payload["data"]
    raise Error, "Dati del prodotto non validi" unless product.is_a?(Hash)

    name = product["name"].to_s.strip
    raise Error, "Prodotto non trovato" if name.empty?

    brand = product["shortDescr"].to_s.strip
    front = Array(product["media"]).find { |media| media["type"] == "front" } || Array(product["media"]).first

    {
      kind: "product",
      title: [name, brand].reject(&:empty?).join(" ").gsub("&", "e"),
      gtin: product["barcode"].to_s.strip,
      quantity: product["description"].to_s.strip,
      image_url: front && (front["medium"] || front["large"]),
      source_url: url.to_s
    }
  end

  # Scarica la foto solo dai negozi noti (l'URL arriva dal client: niente fetch arbitrari)
  def self.fetch_image(url, connection: nil)
    uri = URI.parse(url.to_s.strip)
    host = uri.host.to_s.downcase
    raise Error, "Immagine non valida" unless uri.scheme == "https" && SHOPS.key?(host)

    http = connection || connection_for("https://#{host}")
    response = http.get(uri.request_uri) { |request| request.headers["User-Agent"] = USER_AGENT }
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
    slug = uri.path[%r{\A/(?:shop/)?product/([\w-]+)/?\z}, 1]
    SHOPS.key?(host) && slug ? [host, slug] : nil
  rescue URI::InvalidURIError
    nil
  end

  def self.connection_for(base_url)
    Faraday.new(url: base_url) do |client|
      client.options.open_timeout = 3
      client.options.timeout = 8
    end
  end

  private_class_method :parse, :connection_for
end
