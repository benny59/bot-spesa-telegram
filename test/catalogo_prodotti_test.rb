# frozen_string_literal: true

require "json"
require "rack/mock"
require "tmpdir"

Dir.mktmpdir("catalogo-prodotti-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../api_server", __dir__)

    DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (1, 'Test', -1001, 42)")
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES (?, ?)", ["8000300155877", "Brisée pasta fresca Buitoni 230 g"])
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES (?, ?)", ["5900020043481", "Nestle Fitness Protein Cocoa 310 g"])
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, gtin) VALUES (?, ?, ?, ?, ?)",
      [1, 0, 42, "Brisèe", "8000300155877"]
    )

    backup = {
      kind: "favorites-backup",
      schemaVersion: 1,
      userId: 42,
      favorites: [{ description: "Fitness", gtin: "5900020043481", yukaLink: "https://app.yuka.io/test" }]
    }
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (0, 0, ?, ?, ?)",
      [42, "#{CONFIG_PREFERITI_NOME} & config", JSON.generate(backup)]
    )

    app = Rack::MockRequest.new(Sinatra::Application)
    brisee = JSON.parse(app.get("/prodotti?query=brisee&user_id=42&gruppo_id=1&topic_id=0").body)
    raise "ricerca senza accenti fallita" unless brisee.size == 1
    raise "stato in lista non rilevato" unless brisee.first["in_lista"] == true

    fitness = JSON.parse(app.get("/prodotti?query=fitness+protein&user_id=42&gruppo_id=1&topic_id=0").body)
    raise "ricerca multi-token fallita" unless fitness.size == 1
    raise "link Yuka non recuperato dal preferito" unless fitness.first["yuka_url"] == "https://app.yuka.io/test"
    raise "fonte Yuka errata" unless fitness.first["yuka_source"] == "preferito"

    assente = JSON.parse(app.get("/prodotti?query=inesistente&user_id=42").body)
    raise "ricerca senza risultati non vuota" unless assente.empty?

    # senza parametro limit si restituiscono tutti i risultati (fino a 30), non solo il primo
    35.times { |i| DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES (?, ?)", [format("9%012d", i), "Prodotto Coop numero #{i}"]) }
    tutti = JSON.parse(app.get("/prodotti?query=coop&user_id=42").body)
    raise "il limite predefinito deve essere 30, non 1 (#{tutti.size})" unless tutti.size == 30
    uno = JSON.parse(app.get("/prodotti?query=coop&user_id=42&limit=1").body)
    raise "limit esplicito non rispettato" unless uno.size == 1

    # la ricerca trova anche tramite gli alias (nomi da scontrino), dopo i risultati sul nome
    DataManager.registra_alias_prodotto("8000300155877", "SFOGLIA ROT.FRESCA", negozio: "Coop")
    per_alias = JSON.parse(app.get("/prodotti?query=sfoglia&user_id=42").body)
    raise "alias non cercato" unless per_alias.map { |p| p["gtin"] } == ["8000300155877"]
    nome_prima = JSON.parse(app.get("/prodotti?query=brisee&user_id=42").body)
    raise "il match sul nome deve precedere" unless nome_prima.first["gtin"] == "8000300155877"

    # item_id dell'articolo attivo (per toglierlo), ha_scheda per la I; un articolo già comprato non è "in lista"
    brisee_item = DB.get_first_value("SELECT id FROM items WHERE gtin = '8000300155877'")
    r = JSON.parse(app.get("/prodotti?query=brisee&user_id=42&gruppo_id=1&topic_id=0").body).first
    raise "item_id mancante" unless r["item_id"] == brisee_item && r["in_lista"] == true
    raise "ha_scheda senza metadati" unless r["ha_scheda"] == false
    DataManager.salva_scheda_prodotto({ found: true, barcode: "8000300155877", name: "Brisée", brand: "Buitoni" })
    raise "ha_scheda con metadati" unless JSON.parse(app.get("/prodotti?query=brisee&user_id=42&gruppo_id=1&topic_id=0").body).first["ha_scheda"] == true
    DB.execute("UPDATE items SET comprato = '42' WHERE id = ?", [brisee_item])
    r = JSON.parse(app.get("/prodotti?query=brisee&user_id=42&gruppo_id=1&topic_id=0").body).first
    raise "un articolo già comprato non deve risultare in lista" unless r["in_lista"] == false && r["item_id"].nil?
  end
end

puts "catalogo prodotti: OK"