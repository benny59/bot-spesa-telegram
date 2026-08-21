require_relative "../models/open_food_facts_client"

class FakeOpenFoodFactsConnection
  attr_reader :user_agent

  Response = Struct.new(:body) do
    def success?
      true
    end
  end

  def initialize(body)
    @body = body
  end

  def get(_path, _params)
    request = Struct.new(:headers).new({})
    yield request
    @user_agent = request.headers["User-Agent"]
    Response.new(@body)
  end
end

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

connection = FakeOpenFoodFactsConnection.new(JSON.generate(payload))
OpenFoodFactsClient.lookup(
  "3017624010701",
  user_agent: "BotSpesa/1.1 (test@example.com)",
  connection: connection
)
unless connection.user_agent == "BotSpesa/1.1 (test@example.com)"
  raise "Il client deve usare il User-Agent ricevuto dalla configurazione"
end

puts "OpenFoodFactsClient: OK"