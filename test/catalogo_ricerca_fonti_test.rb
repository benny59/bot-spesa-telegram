# frozen_string_literal: true

require "json"
require "rack/mock"
require "tmpdir"

# La ricerca nel catalogo copre anche preferiti e archivio (anche senza GTIN); un duplicato compare una volta
# sola, nella forma più completa, con `preferito` per la stella.
Dir.mktmpdir("catalogo-fonti-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../api_server", __dir__)

    def fallisci(msg) = (warn "FAIL: #{msg}"; exit 1)

    DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (1, 'Test', -1001, 42), (2, 'Altro', -1002, 42)")
    DB.execute("INSERT INTO categorie (id, gruppo_id, topic_id, nome) VALUES (901, 1, 0, 'Frutta'), (902, 1, 0, 'Dispensa')")
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES (?, ?)", ["8000300155877", "Nettarine sacchetto 1 kg"])

    favoriti = [
      { id: "a", description: "Nettarine gialle", gtin: "8000300155877", categoryId: 901, categoryName: "Frutta" },
      { id: "b", description: "Mix cremoso", gtin: "", categoryId: 902, categoryName: "Dispensa" },
      { id: "c", description: "Nettarine bio", gtin: "" }
    ]
    backup = { kind: "favorites-backup", schemaVersion: 1, userId: 42, favorites: favoriti }
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (0, 0, 42, ?, ?)",
               ["#{CONFIG_PREFERITI_NOME} & config", JSON.generate(backup)])
    # archivio del gruppo 1: una voce senza GTIN (doppione di un preferito), una solo d'archivio, una legata al GTIN
    DB.execute("INSERT INTO storico_articoli (id, gruppo_id, topic_id, nome, last_categoria_id) VALUES (1, 1, 0, 'Mix cremoso', NULL), (2, 1, 0, 'Mix semi', 902), (3, 1, 0, 'Nettarine', 901), (4, 2, 0, 'Mix altro gruppo', NULL)")
    DB.execute("INSERT INTO storico_articolo_prodotti (storico_articolo_id, gtin, utilizzi) VALUES (3, '8000300155877', 1)")

    app = Rack::MockRequest.new(Sinatra::Application)
    cerca = ->(q) { JSON.parse(app.get("/prodotti?query=#{q}&user_id=42&gruppo_id=1&topic_id=0").body) }

    mix = cerca.call("mix")
    nomi = mix.map { |r| r["nome"] }
    fallisci("mix: #{nomi}") unless nomi.sort == ["Mix cremoso", "Mix semi"]   # niente duplicato, niente altro gruppo
    cremoso = mix.find { |r| r["nome"] == "Mix cremoso" }
    fallisci("preferito non segnalato") unless cremoso["preferito"] == true && cremoso["gtin"] == ""
    fallisci("categoria dal preferito persa") unless cremoso["categoria_nome"] == "Dispensa" && cremoso["categoria_id"] == 902
    semi = mix.find { |r| r["nome"] == "Mix semi" }
    fallisci("voce d'archivio") unless semi["preferito"] == false && semi["categoria_nome"] == "Dispensa"
    fallisci("i preferiti vengono prima a pari rilevanza") unless mix.first["nome"] == "Mix cremoso"

    # un GTIN nel catalogo, nei preferiti e nell'archivio: una riga sola, completa, con la stella
    nett = cerca.call("nettarine")
    con_gtin = nett.select { |r| r["gtin"] == "8000300155877" }
    fallisci("GTIN duplicato: #{nett.map { |r| [r['gtin'], r['nome']] }}") unless con_gtin.size == 1
    fallisci("stella del preferito con GTIN") unless con_gtin.first["preferito"] == true && con_gtin.first["nome"] == "Nettarine gialle"
    fallisci("preferito senza GTIN mancante") unless nett.any? { |r| r["nome"] == "Nettarine bio" && r["gtin"] == "" }
    fallisci("la voce d'archivio 'Nettarine' non deve comparire come doppione") if nett.count { |r| r["nome"] == "Nettarine" } > 0

    # si trova per il nome del preferito anche se non è nella descrizione del catalogo
    fallisci("ricerca sul nome del preferito") unless cerca.call("gialle").map { |r| r["gtin"] } == ["8000300155877"]

    # in lista per nome quando manca il GTIN
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (1, 0, 42, 'mix cremoso & Dispensa')")
    r = cerca.call("cremoso").first
    fallisci("in_lista per nome") unless r["in_lista"] == true && r["item_id"]
    puts "OK"
  end
end
