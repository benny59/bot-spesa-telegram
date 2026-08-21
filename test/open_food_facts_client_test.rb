require_relative "../models/open_food_facts_client"

payload = {
  "product" => {
    "code" => "3017624010701",
    "product_name" => "Nutella",
    "brands" => "Ferrero",
    "quantity" => "450 g",
    "image_front_small_url" => "https://example.test/nutella.jpg",
    "nutrition_grades" => "E",
    "nutriments" => {
      "energy-kcal_100g" => 539,
      "sugars_100g" => 56.3,
      "saturated-fat_100g" => 10.6,
      "salt_100g" => 0.107
    }
  }
}

result = OpenFoodFactsClient.normalize(payload, "3017624010701")
expected = {
  name: "Nutella",
  nutriscore_grade: "e",
  energy_kcal_100g: 539,
  saturated_fat_100g: 10.6
}

expected.each do |key, value|
  unless result[key] == value
    raise "#{key}: atteso #{value.inspect}, ottenuto #{result[key].inspect}"
  end
end

unless OpenFoodFactsClient.normalize({ "product" => { "code" => "12345678" } }, "12345678").nil?
  raise "Un prodotto senza nome deve essere ignorato"
end

puts "OpenFoodFactsClient: OK"