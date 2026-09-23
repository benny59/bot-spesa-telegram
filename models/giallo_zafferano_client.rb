require "cgi"
require "faraday"
require "json"
require "uri"

class GialloZafferanoClient
  HOST = "ricette.giallozafferano.it"
  USER_AGENT = "BotSpesa/1.0"

  class Error < StandardError; end

  def self.supports?(url)
    uri = URI.parse(url.to_s.strip)
    uri.scheme == "https" && uri.host.to_s.downcase == HOST && uri.path.end_with?(".html")
  rescue URI::InvalidURIError
    false
  end

  def self.preview(url, connection: nil)
    raise Error, "Link GialloZafferano non valido" unless supports?(url)

    uri = URI.parse(url.to_s.strip)
    http = connection || Faraday.new(url: "https://#{HOST}") do |client|
      client.options.open_timeout = 3
      client.options.timeout = 8
    end
    response = http.get(uri.request_uri) { |request| request.headers["User-Agent"] = USER_AGENT }
    raise Error, "Pagina GialloZafferano non disponibile" unless response.success?

    normalize(response.body, url: uri.to_s)
  rescue URI::InvalidURIError, Faraday::Error, JSON::ParserError => e
    raise Error, "Impossibile leggere la ricetta: #{e.message}"
  end

  def self.normalize(html, url: nil)
    recipe = json_ld_blocks(html).find { |entry| Array(entry["@type"]).include?("Recipe") }
    raise Error, "Dati della ricetta non validi" unless recipe

    title = recipe["name"].to_s.strip
    ingredients = Array(recipe["recipeIngredient"]).map { |item| CGI.unescapeHTML(item.to_s.strip) }.reject(&:empty?)
    raise Error, "Titolo della ricetta mancante" if title.empty?
    raise Error, "Nessun ingrediente importabile" if ingredients.empty?

    {
      title: CGI.unescapeHTML(title),
      servings: recipe["recipeYield"],
      serving_unit: "porzioni",
      ingredients: ingredients,
      source_url: url.to_s
    }
  end

  def self.json_ld_blocks(html)
    html.to_s
      .scan(%r{<script[^>]+type=["']application/ld\+json["'][^>]*>(.*?)</script>}im)
      .flat_map do |match|
        parsed = JSON.parse(CGI.unescapeHTML(match.first.strip))
        parsed.is_a?(Array) ? parsed : [parsed]
      rescue JSON::ParserError
        []
      end
  end

  private_class_method :json_ld_blocks
end