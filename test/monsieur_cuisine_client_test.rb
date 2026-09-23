require_relative "../models/monsieur_cuisine_client"

html = <<~HTML
  <script>window.siteConfig = JSON.parse('{"recipeId":261583}');</script>
HTML
raise "Recipe ID non estratto" unless MonsieurCuisineClient.extract_recipe_id(html) == 261583

payload = {
  "data" => {
    "recipe" => {
      "name" => "Lasagne",
      "defaultServingSizeId" => 2,
      "servingSizes" => [
        {
          "id" => 2,
          "amount" => 4,
          "servingUnit" => "porzioni",
          "ingredientGroups" => [
            { "id" => 10, "name" => "PER IL RAGÙ" },
            { "id" => 20, "name" => "ACCESSORI" }
          ],
          "ingredients" => [
            { "order" => 1, "name" => "Pomodori, a pezzettoni", "amount" => "400", "unit" => "g", "ingredientGroupId" => 10 },
            { "order" => 0, "name" => "Cipolle", "amount" => "120", "unit" => "g", "ingredientGroupId" => 10 },
            { "order" => 2, "name" => "Pirofila", "amount" => "1", "unit" => "", "ingredientGroupId" => 20 }
          ]
        }
      ]
    }
  }
}

result = MonsieurCuisineClient.normalize(payload, url: "https://www.monsieur-cuisine.com/it/recipe/lasagne")
raise "Titolo errato" unless result[:title] == "Lasagne"
raise "Porzioni errate" unless result[:servings] == 4 && result[:serving_unit] == "porzioni"
expected = ["Cipolle 120 g", "Pomodori, a pezzettoni 400 g"]
raise "Ingredienti errati: #{result[:ingredients].inspect}" unless result[:ingredients] == expected

puts "MonsieurCuisineClient: OK"