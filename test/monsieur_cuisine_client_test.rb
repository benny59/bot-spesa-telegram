require_relative "../models/recipe_importer"

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

giallo_zafferano_html = <<~HTML
  <script type="application/ld+json">
    {"@type":"Recipe","name":"Tiramisù","recipeYield":10,"recipeIngredient":["Mascarpone 1 kg","Cacao amaro in polvere q.b."]}
  </script>
HTML
giallo_zafferano = GialloZafferanoClient.normalize(
  giallo_zafferano_html,
  url: "https://ricette.giallozafferano.it/Tiramisu.html"
)
raise "Titolo GialloZafferano errato" unless giallo_zafferano[:title] == "Tiramisù"
raise "Porzioni GialloZafferano errate" unless giallo_zafferano[:servings] == 10
raise "Ingredienti GialloZafferano errati" unless giallo_zafferano[:ingredients].size == 2
raise "Dispatcher Monsieur Cuisine non valido" unless RecipeImporter.supports?("https://www.monsieur-cuisine.com/it/recipe/lasagne")
raise "Dispatcher GialloZafferano non valido" unless RecipeImporter.supports?("https://ricette.giallozafferano.it/Tiramisu.html")
raise "Dominio estraneo accettato" if RecipeImporter.supports?("https://example.com/recipe/test")

puts "RecipeImporter: OK"