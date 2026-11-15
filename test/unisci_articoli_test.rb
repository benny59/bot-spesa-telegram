# frozen_string_literal: true

require "json"
require "rack/mock"
require "tmpdir"

# Caso reale (Giovi): articolo Tigros con GTIN e foto + articolo Yuka senza GTIN, stesso prodotto.
Dir.mktmpdir("unisci-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../api_server", __dir__)

    def fallisci(msg) = (warn "FAIL: #{msg}"; exit 1)

    DB.execute("CREATE TABLE memberships (user_id INTEGER NOT NULL, gruppo_id INTEGER NOT NULL)")
    DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (1, 'Test', -1001, 42)")
    DB.execute("INSERT INTO memberships (user_id, gruppo_id) VALUES (42, 1)")
    DB.execute("INSERT INTO categorie (id, gruppo_id, topic_id, nome) VALUES (43, 1, 1451, 'Surgelati')")
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES ('80476504', 'SFOGLIAVELO CON PROSCIUTTO CRUDO RANA')")
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, gtin, comprato, categoria_id) VALUES (10, 1, 1451, 42, 'SFOGLIAVELO CON PROSCIUTTO CRUDO RANA', '80476504', '', 43)")
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, link_url, comprato, categoria_id) VALUES (11, 1, 1451, 42, 'Sfogliavelo Prosciutto Crudo', 'https://app.yuka.io/yenXf3R', '', 43)")
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, gtin, comprato) VALUES (12, 1, 1451, 42, 'Altro', '5900020043481', '')")
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, comprato) VALUES (13, 1, 0, 42, 'Altra lista', '')")
    DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (10, 'F', 'U')")
    DB.execute("INSERT INTO storico_articoli (id, gruppo_id, topic_id, nome, conteggio) VALUES (1, 1, 1451, 'Sfogliavelo con prosciutto crudo rana', 1), (2, 1, 1451, 'Sfogliavelo prosciutto crudo', 1)")

    app = Rack::MockRequest.new(Sinatra::Application)
    chiama = ->(corpo) { app.post("/lista/unisci", input: { gruppo_id: 1, user_id: 42 }.merge(corpo).to_json, "CONTENT_TYPE" => "application/json") }

    # anteprima: non scrive nulla
    r = chiama.call(ids: [11, 10], anteprima: true)
    fallisci("anteprima #{r.status} #{r.body}") unless r.status == 200
    a = JSON.parse(r.body)
    fallisci("tiene il più completo (Tigros)") unless a["tieni_id"] == 10 && a["elimina_ids"] == [11]
    fallisci("GTIN/link/foto previsti") unless a["gtin"] == "80476504" && a["link_url"] == "https://app.yuka.io/yenXf3R" && a["foto"] == true
    fallisci("l'anteprima ha scritto") unless DB.get_first_value("SELECT deleted FROM items WHERE id = 11") == 0

    # GTIN diversi, liste diverse, id sconosciuto
    fallisci("GTIN diversi accettati") unless chiama.call(ids: [10, 12]).status == 422
    fallisci("liste diverse accettate") unless chiama.call(ids: [10, 13]).status == 422
    fallisci("id mancante") unless chiama.call(ids: [10, 999]).status == 404
    fallisci("un solo id") unless chiama.call(ids: [10]).status == 400

    r = chiama.call(ids: [10, 11], nome: "Sfogliavelo prosciutto crudo Rana")
    fallisci("unione #{r.status} #{r.body}") unless r.status == 200
    tenuto = DB.get_first_row("SELECT * FROM items WHERE id = 10")
    fallisci("nome scelto") unless tenuto["nome"] == "Sfogliavelo prosciutto crudo Rana"
    fallisci("link Yuka non copiato") unless tenuto["link_url"] == "https://app.yuka.io/yenXf3R" && tenuto["gtin"] == "80476504"
    fallisci("l'altro non è cancellato (annullabile)") unless DB.get_first_value("SELECT deleted FROM items WHERE id = 11") == 1
    fallisci("foto persa") unless DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = 10") == 1
    fallisci("archivio non unito: #{DB.execute('SELECT nome, conteggio FROM storico_articoli')}") unless DB.get_first_value("SELECT COUNT(*) FROM storico_articoli") == 1 && DB.get_first_value("SELECT conteggio FROM storico_articoli") == 2

    # la foto dell'articolo scartato passa a quello tenuto se questo non ne ha
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, comprato) VALUES (20, 1, 5, 42, 'Pane A', ''), (21, 1, 5, 42, 'Pane B', '')")
    DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (21, 'F2', 'U2')")
    r = chiama.call(ids: [20, 21], tieni_id: 20)
    fallisci("unione senza foto #{r.body}") unless r.status == 200 && DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = 20") == 1

    # tre articoli: EAN-8 e la stessa cosa in forma GTIN-13 con zeri davanti (Coop) sono lo stesso prodotto
    fallisci("GTIN canonico") unless DataManager.normalizza_gtin("0000080476504") == "80476504"
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, gtin, comprato) VALUES (40, 1, 9, 42, 'Ravioli A', '80476504', ''), (41, 1, 9, 42, 'Ravioli B', '0000080476504', ''), (42, 1, 9, 42, 'Ravioli C', NULL, '')")
    DB.execute("UPDATE items SET link_url = 'https://app.yuka.io/z' WHERE id = 42")
    DB.execute("INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (41, 'F3', 'U3')")
    r = chiama.call(ids: [40, 41, 42], anteprima: true)
    fallisci("tre articoli #{r.body}") unless r.status == 200 && JSON.parse(r.body)["gtin"] == "80476504"
    r = chiama.call(ids: [40, 41, 42])
    j = JSON.parse(r.body)
    fallisci("unione a tre #{r.body}") unless r.status == 200 && j["elimina_ids"].size == 2
    t = DB.get_first_row("SELECT * FROM items WHERE id = ?", [j["tieni_id"]])
    fallisci("GTIN/link/foto dei tre") unless t["gtin"] == "80476504" && t["link_url"] == "https://app.yuka.io/z" && DB.get_first_value("SELECT COUNT(*) FROM item_images WHERE item_id = ?", [t["id"]]) == 1
    fallisci("gli altri due cancellati") unless DB.get_first_value("SELECT COUNT(*) FROM items WHERE id IN (40,41,42) AND deleted = 1") == 2

    # migrazione: il prodotto salvato con gli zeri si fonde con quello canonico e resta cercabile come alias
    DB.execute("INSERT OR IGNORE INTO prodotti (gtin, descrizione) VALUES ('80476504', 'Sfogliavelo canonico')")
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES ('0000080476504', 'Ravioli sfogliavelo RANA')")
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, gtin, comprato) VALUES (50, 1, 9, 42, 'Z', '0000080476504', '')")
    DataManager.canonicalizza_gtin_esistenti
    fallisci("prodotto non fuso") unless DB.get_first_value("SELECT COUNT(*) FROM prodotti WHERE gtin LIKE '%80476504'") == 1
    fallisci("item non canonico") unless DB.get_first_value("SELECT gtin FROM items WHERE id = 50") == "80476504"
    fallisci("alias non registrato") unless DB.get_first_value("SELECT COUNT(*) FROM prodotto_alias WHERE gtin = '80476504'") == 1
    fallisci("migrazione non idempotente") unless DataManager.canonicalizza_gtin_esistenti == 0

    # GTIN già in lista: si completa l'esistente, nessun doppione
    DB.execute("INSERT INTO items (id, gruppo_id, topic_id, creato_da, nome, gtin, comprato) VALUES (30, 1, 7, 42, 'Acqua Fonte', '8006290802012', '')")
    DB.execute("INSERT INTO prodotti (gtin, descrizione) VALUES ('8006290802012', 'Acqua Fonte')")
    r = app.post("/lista", input: { gruppo_id: 1, topic_id: 7, user_id: 42, nome: "Altro nome", gtin: "8006290802012", link_url: "https://app.yuka.io/x", split_items: false }.to_json, "CONTENT_TYPE" => "application/json")
    j = JSON.parse(r.body)
    fallisci("GTIN doppio creato #{r.body}") unless j["item_ids"] == [30] && j["esistenti"] == [30]
    fallisci("link non completato") unless DB.get_first_value("SELECT link_url FROM items WHERE id = 30") == "https://app.yuka.io/x"
    fallisci("nome sovrascritto") unless DB.get_first_value("SELECT nome FROM items WHERE id = 30") == "Acqua Fonte"
    # un articolo nuovo non è tra gli esistenti
    r = app.post("/lista", input: { gruppo_id: 1, topic_id: 7, user_id: 42, nome: "Latte", split_items: false }.to_json, "CONTENT_TYPE" => "application/json")
    fallisci("nuovo come esistente") unless JSON.parse(r.body)["esistenti"] == []
    puts "OK"
  end
end
