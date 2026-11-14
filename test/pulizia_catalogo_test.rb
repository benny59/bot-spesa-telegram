# frozen_string_literal: true

require "tmpdir"

Dir.mktmpdir("pulizia-catalogo-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../handlers/cleanup_manager", __dir__)

    vecchio = "datetime('now', '-400 days')"
    nuovo = lambda do |gtin, creato: vecchio, controllo: nil|
      DB.execute("INSERT INTO prodotti (gtin, descrizione, creato_il, ultimo_controllo) VALUES (?, ?, #{creato}, #{controllo || 'NULL'})", [gtin, "p#{gtin}"])
    end
    storico = lambda do |gtin, utilizzi:, ultimo:|
      DB.execute("INSERT INTO storico_articoli (gruppo_id, topic_id, nome) VALUES (1, 0, ?)", ["s#{gtin}#{utilizzi}#{ultimo}"])
      sid = DB.last_insert_row_id
      DB.execute("INSERT INTO storico_articolo_prodotti (storico_articolo_id, gtin, utilizzi, ultimo_utilizzo, ultimo_acquisto) VALUES (?, ?, ?, datetime('now', ?), datetime('now', ?))", [sid, gtin, utilizzi, ultimo, ultimo])
    end

    da_togliere  = "8000300155877"   # vecchio, mai usato
    uso_vecchio  = "3017624010701"   # un solo uso, 400 giorni fa
    preferito    = "5900020043481"   # vecchio ma preferito di qualcuno
    in_lista     = "4000358091107"   # vecchio ma in un articolo ancora in lista
    due_usi      = "8076809513722"   # due usi
    uso_recente  = "8023788050977"   # un solo uso ma recente
    appena_nato  = "8000500310427"   # creato da poco
    scansionato  = "8001120013958"   # vecchio ma controllato/scansionato da poco

    [da_togliere, uso_vecchio, preferito, in_lista, due_usi, uso_recente].each { |g| nuovo.call(g) }
    nuovo.call(appena_nato, creato: "datetime('now', '-10 days')")
    nuovo.call(scansionato, controllo: "datetime('now', '-20 days')")
    storico.call(uso_vecchio, utilizzi: 1, ultimo: "-400 days")
    storico.call(due_usi, utilizzi: 2, ultimo: "-500 days")
    storico.call(uso_recente, utilizzi: 1, ultimo: "-30 days")
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, gtin) VALUES (1, 0, 1, 'x', ?)", [in_lista])
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (0, 0, 7, ?, ?)",
               [DataManager::CONFIG_PREFERITI_NOME, JSON.generate(favorites: [{ "id" => "a", "description" => "x", "gtin" => preferito }])])
    DataManager.registra_alias_prodotto(da_togliere, "alias da togliere", negozio: "Coop")

    candidati = DataManager.prodotti_catalogo_scaduti.map { |r| r["gtin"] }.sort
    attesi = [da_togliere, uso_vecchio].sort
    raise "candidati errati: #{candidati.inspect} (attesi #{attesi.inspect})" unless candidati == attesi

    # il passo del cleanup toglie prodotto, alias e righe di storico, e lascia stare gli altri
    n = CleanupManager.pulisci_catalogo_prodotti
    raise "rimossi #{n}" unless n == 2
    rimasti = DB.execute("SELECT gtin FROM prodotti").map { |r| r["gtin"] }
    raise "prodotti protetti rimossi" unless ([preferito, in_lista, due_usi, uso_recente, appena_nato, scansionato] - rimasti).empty?
    raise "prodotti da togliere rimasti" unless (rimasti & [da_togliere, uso_vecchio]).empty?
    raise "alias non tolti" unless DB.get_first_value("SELECT COUNT(*) FROM prodotto_alias WHERE gtin = ?", [da_togliere]).to_i.zero?
    raise "storico del prodotto tolto non rimosso" unless DB.get_first_value("SELECT COUNT(*) FROM storico_articolo_prodotti WHERE gtin = ?", [uso_vecchio]).to_i.zero?
    raise "storico dei prodotti protetti perso" unless DB.get_first_value("SELECT COUNT(*) FROM storico_articolo_prodotti WHERE gtin IN (?, ?)", [due_usi, uso_recente]).to_i == 2

    # idempotente, e righe orfane (voce di storico cancellata) ripulite
    raise "seconda esecuzione non vuota" unless CleanupManager.pulisci_catalogo_prodotti.zero?
    DB.execute("DELETE FROM storico_articoli")
    raise "righe orfane non contate" unless DataManager.pulisci_righe_storico_prodotti_orfane == 2

    # un prodotto nuovo prende la data di creazione dal trigger
    DataManager.upsert_prodotto("4005500341802", "nuovo")
    raise "creato_il non impostato dal trigger" if DB.get_first_value("SELECT creato_il FROM prodotti WHERE gtin = '4005500341802'").to_s.empty?
    puts "pulizia_catalogo_test OK"
  end
end
