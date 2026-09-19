require "faraday"
require "json"

class OpenFoodFactsClient
  BASE_URL = "https://world.openfoodfacts.org"
  FIELDS = %w[
    code
    product_name
    brands
    quantity
    image_front_url
    image_front_small_url
    manufacturing_places
    nutrition_grades
    nova_group
    additives_tags
    allergens_tags
    ingredients_text
    completeness
    nutriments
  ].join(",")

  def self.lookup(barcode, user_agent:, connection: nil)
    code = barcode.to_s.gsub(/\D/, "")
    return nil unless code.match?(/\A\d{8,14}\z/)

    http = connection || Faraday.new(url: BASE_URL) do |client|
      client.options.open_timeout = 3
      client.options.timeout = 5
    end
    response = http.get("/api/v2/product/#{code}.json", { fields: FIELDS }) do |request|
      request.headers["User-Agent"] = user_agent
    end
    return nil unless response.success?

    normalize(JSON.parse(response.body), code)
  rescue Faraday::Error, JSON::ParserError
    nil
  end

  def self.normalize(payload, fallback_code = nil)
    product = payload["product"]
    return nil unless product.is_a?(Hash)

    nutriments = product["nutriments"].is_a?(Hash) ? product["nutriments"] : {}
    name = product["product_name"].to_s.strip
    return nil if name.empty?

    {
      found: true,
      barcode: product["code"].to_s.strip.empty? ? fallback_code.to_s : product["code"].to_s,
      name: name,
      brand: product["brands"].to_s.strip,
      quantity: product["quantity"].to_s.strip,
      image_url: first_present(product["image_front_url"], product["image_front_small_url"]),
      manufacturing_places: product["manufacturing_places"].to_s.strip,
      nutriscore_grade: product["nutrition_grades"].to_s.downcase,
      nova_group: integer_value(product["nova_group"]),
      additives: tag_values(product["additives_tags"]),
      allergens: tag_values(product["allergens_tags"]),
      ingredients_text: product["ingredients_text"].to_s.strip,
      completeness: numeric_value(product["completeness"]),
      energy_kcal_100g: nutrient_value(nutriments, "energy-kcal_100g", "energy_kcal_100g"),
      sugars_100g: nutrient_value(nutriments, "sugars_100g"),
      saturated_fat_100g: nutrient_value(nutriments, "saturated-fat_100g", "saturated_fat_100g"),
      salt_100g: nutrient_value(nutriments, "salt_100g"),
      source_url: "https://world.openfoodfacts.org/product/#{fallback_code}"
    }
  end

  def self.nutrient_value(nutriments, *keys)
    value = keys.lazy.map { |key| nutriments[key] }.find { |candidate| !candidate.nil? }
    numeric_value(value)
  end

  def self.numeric_value(value)
    value.is_a?(Numeric) ? value : nil
  end

  def self.integer_value(value)
    value.is_a?(Numeric) ? value.to_i : nil
  end

  def self.first_present(*values)
    values.map { |value| value.to_s.strip }.find { |value| !value.empty? }.to_s
  end

  def self.tag_values(value)
    return [] unless value.is_a?(Array)

    value.filter_map do |tag|
      normalized = tag.to_s.sub(/\A[a-z]{2}:/, "").tr("-", " ").strip
      normalized unless normalized.empty?
    end
  end

  private_class_method :first_present, :integer_value, :nutrient_value, :numeric_value, :tag_values
end