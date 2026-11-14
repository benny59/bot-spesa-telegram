# frozen_string_literal: true

require "tmpdir"

Dir.mktmpdir("prodotto-alias-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)

    gtin = "3017624010701"
    DataManager.upsert_prodotto(gtin, "Nutella 450 g")

    raise "alias su GTIN sconosciuto" if DataManager.registra_alias_prodotto("8000500310427", "Crema", negozio: "Coop")
    raise "alias su GTIN invalido" if DataManager.registra_alias_prodotto("3017624010702", "Crema nocciole")
    raise "alias troppo corto accettato" if DataManager.registra_alias_prodotto(gtin, "ab")
    raise "alias uguale alla descrizione accettato" if DataManager.registra_alias_prodotto(gtin, "NUTELLA 450 g")

    raise "primo alias non nuovo" unless DataManager.registra_alias_prodotto(gtin, "NUTELLA  Ferrero 450G", negozio: "Coop") == :nuovo
    raise "alias ripetuto non riconosciuto" unless DataManager.registra_alias_prodotto(gtin, "nutella ferrero 450g", negozio: "COOP") == :esistente
    raise "stesso alias su altro negozio deve essere distinto" unless DataManager.registra_alias_prodotto(gtin, "nutella ferrero 450g", negozio: "Tigros") == :nuovo

    20.times { |i| DataManager.registra_alias_prodotto(gtin, "variante numero #{i}", negozio: "Coop") }
    n = DB.get_first_value("SELECT COUNT(*) FROM prodotto_alias WHERE gtin = ?", [gtin]).to_i
    raise "tetto alias superato (#{n})" unless n == DataManager::MAX_ALIAS_PER_PRODOTTO


    # Priorità del nome: preferito > storico > scontrino
    g2 = "8000500310427"
    DB.execute("INSERT INTO prodotti (gtin, descrizione, descrizione_origine) VALUES (?, ?, 'scontrino')", [g2, "CREMA NOC 400G"])
    raise "scontrino non deve scavalcare scontrino" if DataManager.imposta_descrizione(g2, "ALTRA CREMA", "scontrino")
    raise "storico deve scavalcare scontrino" unless DataManager.imposta_descrizione(g2, "Crema di nocciole", "storico")
    raise "scontrino non deve scavalcare storico" if DataManager.imposta_descrizione(g2, "CREMA NOC 400G", "scontrino")
    raise "preferito deve scavalcare storico" unless DataManager.imposta_descrizione(g2, "la crema buona", "preferito")
    raise "storico non deve scavalcare preferito" if DataManager.imposta_descrizione(g2, "Crema di nocciole", "storico")
    raise "descrizione errata" unless DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [g2]) == "la crema buona"
    raise "nome sostituito non conservato come alias" unless DB.get_first_value("SELECT COUNT(*) FROM prodotto_alias WHERE gtin = ? AND alias = 'crema di nocciole'", [g2]).to_i == 1
    # Open Food Facts non scavalca preferito/storico
    DataManager.salva_scheda_prodotto({ barcode: g2, name: "Nutella", brand: "Ferrero", quantity: "400 g" })
    raise "OFF ha sovrascritto il nome del preferito" unless DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [g2]) == "la crema buona"
    # Fonti: preferito dal backup, storico dallo storico
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (0, 0, 7, ?, ?)",
               [DataManager::CONFIG_PREFERITI_NOME, JSON.generate(favorites: [{ description: "Latte del mattino", gtin: "8000300155877" }])])
    DataManager.upsert_prodotto("8000300155877", nil)
    DB.execute("UPDATE prodotti SET descrizione = 'LATTE PS', descrizione_origine = 'scontrino' WHERE gtin = '8000300155877'")
    raise "riallineo da preferito fallito" unless DataManager.riallinea_descrizione("8000300155877") == "preferito"
    raise "nome preferito non applicato" unless DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = '8000300155877'") == "Latte del mattino"

    # transazione: con applica false annulla, con true conferma
    nuovo = "5900020043481"
    DataManager.transazione(applica: false) { DataManager.upsert_prodotto(nuovo, "x") }
    raise "dry-run ha scritto" if DB.get_first_value("SELECT COUNT(*) FROM prodotti WHERE gtin = ?", [nuovo]).to_i.positive?
    DataManager.transazione(applica: true) { DataManager.upsert_prodotto(nuovo, "x") }
    raise "apply non ha scritto" unless DB.get_first_value("SELECT COUNT(*) FROM prodotti WHERE gtin = ?", [nuovo]).to_i == 1
    puts "prodotto_alias_test OK"
  end
end
