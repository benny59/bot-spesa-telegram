require "faraday"
require "json"

class OpenFoodFactsClient
  BASE_URL = "https://world.openfoodfacts.org"
  FIELDS = %w[
    code
    product_name
    brands
    quantity
    image_front_small_url
    nutrition_grades
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
      image_url: product["image_front_small_url"].to_s.strip,
      nutriscore_grade: product["nutrition_grades"].to_s.downcase,
      energy_kcal_100g: nutrient_value(nutriments, "energy-kcal_100g", "energy_kcal_100g"),
      sugars_100g: nutrient_value(nutriments, "sugars_100g"),
      saturated_fat_100g: nutrient_value(nutriments, "saturated-fat_100g", "saturated_fat_100g"),
      salt_100g: nutrient_value(nutriments, "salt_100g"),
      source_url: "https://world.openfoodfacts.org/product/#{fallback_code}"
    }
  end

  def self.nutrient_value(nutriments, *keys)
    value = keys.lazy.map { |key| nutriments[key] }.find { |candidate| !candidate.nil? }
    value.is_a?(Numeric) ? value : nil
  end

  private_class_method :nutrient_value
end