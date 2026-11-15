require "json"
require "uri"
require_relative "ebsn_shop_client"

# Scheda prodotto di Conad Spesa Online: pagina HTML con dati strutturati schema.org (JSON-LD "Product").
# Stessa forma di risposta dei negozi EBSN, così PWA e importazione non distinguono il negozio.
class ConadClient
  HOST = "spesaonline.conad.it".freeze
  Error = EbsnShopClient::Error
  LD_JSON = %r{<script[^>]*type="application/ld\+json"[^>]*>(.*?)</script>}m
  OG_IMAGE = /<meta[^>]*property="og:image"[^>]*content="([^"]+)"/

  def self.supports?(url)
    !parse(url).nil?
  end

  def self.preview(url, connection: nil)
    raise Error, "Link negozio non supportato" unless parse(url)

    http = connection || EbsnShopClient.connection_for("https://#{HOST}")
    response = EbsnShopClient.get(http, URI.parse(url.to_s.strip).request_uri)
    raise Error, "Prodotto Conad non disponibile" unless response.success?

    normalize(response.body.to_s.dup.force_encoding(Encoding::UTF_8), url: url.to_s.strip)
  rescue Faraday::Error => e
    raise Error, "Impossibile leggere il prodotto: #{e.message}"
  end

  def self.normalize(html, url: nil)
    product = html.scan(LD_JSON).filter_map { |(json)| JSON.parse(json) rescue nil }
                  .find { |data| data.is_a?(Hash) && data["@type"] == "Product" }
    raise Error, "Dati del prodotto non validi" unless product

    name = product["name"].to_s.sub(/\s*\|\s*Conad\s*\z/i, "").strip
    raise Error, "Prodotto non trovato" if name.empty?

    {
      kind: "product",
      title: name.gsub("&", "e"),
      gtin: product["gtin"].to_s.strip,
      quantity: "",
      image_url: html[OG_IMAGE, 1],
      source_url: url.to_s
    }
  end

  def self.fetch_image(url, connection: nil) = EbsnShopClient.download_image(url, hosts: [HOST], connection: connection)

  def self.image_host?(url)
    URI.parse(url.to_s.strip).host.to_s.downcase == HOST
  rescue URI::InvalidURIError
    false
  end

  # => true/nil: solo https://spesaonline.conad.it/p/<slug>--<codice> (il codice può avere suffissi, es. 7270889-1_N)
  def self.parse(url)
    uri = URI.parse(url.to_s.strip)
    uri.scheme == "https" && uri.host.to_s.downcase == HOST && uri.path.match?(%r{\A/p/[^/]+--[\w-]+/?\z}) ? true : nil
  rescue URI::InvalidURIError
    nil
  end

  private_class_method :parse
end
