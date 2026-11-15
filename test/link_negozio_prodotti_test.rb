# frozen_string_literal: true

require "json"
require "rack/mock"
require "tmpdir"

# Link CoopShop/Tigros -> anteprima con GTIN normalizzato; l'aggiunta con GTIN alimenta `prodotti` con la sola descrizione.
Dir.mktmpdir("link-negozio-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../api_server", __dir__)

    def fallisci(msg) = (warn "FAIL: #{msg}"; exit 1)

    DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (1, 'Test', -1001, 42)")

    [["0000000000412", ""], ["8006290802012", "8006290802012"]].each do |grezzo, atteso|
      RecipeImporter.define_singleton_method(:preview) { |_url| { kind: "product", title: "Acqua", gtin: grezzo } }
      risposta = Rack::MockRequest.new(Sinatra::Application)
                                  .post("/import/recipe/preview", input: { url: "https://www.coopshop.it/product/x" }.to_json, "CONTENT_TYPE" => "application/json")
      gtin = JSON.parse(risposta.body)["gtin"] if risposta.status == 200
      fallisci("preview #{grezzo} -> #{risposta.status} #{risposta.body}") unless gtin == atteso
    end

    DataManager.aggiungi_articoli(gruppo_id: 1, user_id: 42, items_text: "Acqua naturale & Bevande", gtin: "8006290802012", split_items: false)
    riga = DB.get_first_row("SELECT descrizione FROM prodotti WHERE gtin = '8006290802012'")
    fallisci("descrizione catalogo: #{riga.inspect}") unless riga && riga["descrizione"] == "Acqua naturale"
    puts "OK"
  end
end
