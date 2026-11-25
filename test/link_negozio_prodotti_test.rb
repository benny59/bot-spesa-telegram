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
    DB.execute("CREATE TABLE IF NOT EXISTS memberships (user_id INTEGER, gruppo_id INTEGER, last_seen DATETIME)")
    DB.execute("INSERT INTO memberships (user_id, gruppo_id) VALUES (42, 1)")

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
    # le liste dicono ai client quali link sono di un negozio: il client non ha elenchi di domini
    link = {
      "Quark" => ["https://www.naturasi.it/prodotti/quark-magro-35050", true],
      "Passata" => ["https://www.tigros.it/product/passata", true],
      "Sapone" => ["https://app.yuka.io/x", false],
      "Pane" => ["", false]
    }
    link.each { |nome, (url, _)| DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (1, 0, 42, ?, ?)", [nome, url]) }
    ["/lista?gruppo_id=1&topic_id=0&user_id=42", "/lista/miei?user_id=42"].each do |percorso|
      risposta = Rack::MockRequest.new(Sinatra::Application).get(percorso)
      fallisci("#{percorso} -> #{risposta.status} #{risposta.body}") unless risposta.status == 200
      articoli = JSON.parse(risposta.body).to_h { |item| [item["nome"], item["link_negozio"]] }
      link.each { |nome, (_, atteso)| fallisci("#{percorso} #{nome}: #{articoli[nome].inspect}") unless articoli[nome] == atteso }
    end
    puts "OK"
  end
end
