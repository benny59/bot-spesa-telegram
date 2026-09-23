require "faraday"
require "json"
require "uri"

class MonsieurCuisineClient
  SITE_HOST = "www.monsieur-cuisine.com"
  API_URL = "https://mc-api.tecpal.com"
  USER_AGENT = "BotSpesa/1.0"

  class Error < StandardError; end

  def self.preview(url, page_connection: nil, api_connection: nil)
    uri = validate_url(url)
    language = uri.path.split("/").reject(&:empty?).first.to_s.downcase
    language = "it" unless language.match?(/\A[a-z]{2}(?:-[a-z]{2})?\z/)

    page_http = page_connection || connection("https://#{SITE_HOST}")
    page_response = page_http.get(uri.request_uri) do |request|
      request.headers["User-Agent"] = USER_AGENT
    end
    raise Error, "Pagina Monsieur Cuisine non disponibile" unless page_response.success?

    recipe_id = extract_recipe_id(page_response.body)
    raise Error, "Ricetta Monsieur Cuisine non riconosciuta" unless recipe_id

    api_http = api_connection || connection(API_URL)
    api_response = api_http.get("/api/v2/recipes/#{recipe_id}") do |request|
      request.headers["Accept-Language"] = locale_for(language)
      request.headers["device-type"] = "web"
      request.headers["User-Agent"] = USER_AGENT
    end
    raise Error, "Dettagli della ricetta non disponibili" unless api_response.success?

    normalize(JSON.parse(api_response.body), url: uri.to_s)
  rescue URI::InvalidURIError, Faraday::Error, JSON::ParserError => e
    raise Error, "Impossibile leggere la ricetta: #{e.message}"
  end

  def self.extract_recipe_id(html)
    html.to_s[/["']recipeId["']\s*:\s*(\d+)/, 1]&.to_i
  end

  def self.normalize(payload, url: nil)
    recipe = payload.dig("data", "recipe")
    raise Error, "Dati della ricetta non validi" unless recipe.is_a?(Hash)

    title = recipe["name"].to_s.strip
    raise Error, "Titolo della ricetta mancante" if title.empty?

    serving_sizes = recipe["servingSizes"]
    raise Error, "Ingredienti della ricetta mancanti" unless serving_sizes.is_a?(Array)

    default_id = recipe["defaultServingSizeId"].to_i
    serving = serving_sizes.find { |candidate| candidate["id"].to_i == default_id } || serving_sizes.first
    raise Error, "Ingredienti della ricetta mancanti" unless serving.is_a?(Hash)

    excluded_group_ids = Array(serving["ingredientGroups"]).filter_map do |group|
      group["id"].to_i if group["name"].to_s.strip.casecmp?("ACCESSORI")
    end
    ingredients = Array(serving["ingredients"])
      .reject { |ingredient| excluded_group_ids.include?(ingredient["ingredientGroupId"].to_i) }
      .sort_by { |ingredient| ingredient["order"].to_i }
      .filter_map { |ingredient| format_ingredient(ingredient) }
    raise Error, "Nessun ingrediente importabile" if ingredients.empty?

    {
      title: title,
      servings: serving["amount"],
      serving_unit: serving["servingUnit"].to_s.strip,
      ingredients: ingredients,
      source_url: url.to_s
    }
  end

  def self.validate_url(raw_url)
    uri = URI.parse(raw_url.to_s.strip)
    normalized_host = uri.host.to_s.downcase.sub(/\Amonsieur-cuisine\.com\z/, SITE_HOST)
    valid_path = uri.path.match?(%r{\A/[a-z]{2}(?:-[a-z]{2})?/recipe/[^/]+/?\z}i)
    raise Error, "Link Monsieur Cuisine non valido" unless uri.scheme == "https" && normalized_host == SITE_HOST && valid_path

    uri.host = SITE_HOST
    uri
  end

  def self.connection(base_url)
    Faraday.new(url: base_url) do |client|
      client.options.open_timeout = 3
      client.options.timeout = 8
    end
  end

  def self.locale_for(language)
    return "it-IT" if language == "it"

    language.include?("-") ? language : "#{language}-#{language.upcase}"
  end

  def self.format_ingredient(ingredient)
    name = ingredient["name"].to_s.strip
    return nil if name.empty?

    [name, ingredient["amount"].to_s.strip, ingredient["unit"].to_s.strip]
      .reject(&:empty?)
      .join(" ")
  end

  private_class_method :connection, :format_ingredient, :locale_for, :validate_url
end