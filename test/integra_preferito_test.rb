# frozen_string_literal: true

require "tmpdir"

Dir.mktmpdir("integra-preferito-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)

    gtin = "8000300155877"
    link = "https://app.yuka.io/products/brisee-123"
    DataManager.upsert_prodotto(gtin, "Brisée stesa")
    DataManager.registra_alias_prodotto(gtin, "BRISEE STESA 230G", negozio: "Coop")
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url, gtin) VALUES (0, 0, 7, 'Pasta brisee', ?, ?)", [link, gtin])

    # 1) GTIN dal link Yuka; nome, categoria e foto invariati
    fav, mod, = DataManager.integra_preferito({ "description" => "la sfoglia", "yukaLink" => link, "categoryId" => 5, "telegramPhotoId" => "x" })
    raise "gtin da link non ricavato" unless fav["gtin"] == gtin && mod.include?("GTIN da link Yuka")
    raise "campi del preferito alterati" unless fav["description"] == "la sfoglia" && fav["categoryId"] == 5 && fav["telegramPhotoId"] == "x"
    raise "il nome del preferito deve diventare descrizione" unless DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [gtin]) == "la sfoglia"

    # 2) link Yuka dal GTIN
    fav, mod, = DataManager.integra_preferito({ "description" => "sfoglia", "gtin" => gtin })
    raise "link Yuka non ricavato dal gtin" unless fav["yukaLink"] == link && mod == ["link Yuka"]

    # 3) nome identico a un alias -> gtin; nome solo simile -> NON applicato ma segnalato
    fav, mod, = DataManager.integra_preferito({ "description" => "brisee stesa 230g" })
    raise "gtin da nome identico non ricavato" unless fav["gtin"] == gtin
    fav, mod, simili = DataManager.integra_preferito({ "description" => "brisee" })
    raise "nome simile applicato in automatico" if fav["gtin"] || !mod.empty?
    raise "nome simile non segnalato" unless simili.map(&:first) == [gtin]

    # 4) idempotenza
    fav, = DataManager.integra_preferito({ "description" => "la sfoglia", "yukaLink" => link, "gtin" => gtin })
    _, mod, = DataManager.integra_preferito(fav)
    raise "seconda integrazione non idempotente" unless mod.empty?

    # 5) duplicati: stesso GTIN, stesso link, stesso nome normalizzato; i diversi restano fuori
    dup = DataManager.duplicati_preferiti([
      { "description" => "Muesli", "gtin" => gtin }, { "description" => "Muesli COOP", "gtin" => gtin },
      { "description" => "Pane", "yukaLink" => link }, { "description" => "pane!!" },
      { "description" => "Latte" }
    ])
    raise "duplicati errati: #{dup.inspect}" unless dup.sort == [["Muesli", "Muesli COOP"], ["Pane", "pane!!"]].sort

    # 6) salvataggio backup: l'integrazione già fatta non si perde se l'app manda il preferito senza codici
    salvato = { "favorites" => [{ "id" => "a", "description" => "la sfoglia", "gtin" => gtin, "yukaLink" => link }] }
    in_arrivo = { "favorites" => [{ "id" => "a", "description" => "la sfoglia" }, { "id" => "b", "description" => "brisee stesa 230g" }] }
    nuovo, n = DataManager.integra_backup_preferiti(in_arrivo, salvato)
    raise "gtin/link persi nel backup" unless nuovo["favorites"][0]["gtin"] == gtin && nuovo["favorites"][0]["yukaLink"] == link
    raise "nuovo preferito non integrato" unless nuovo["favorites"][1]["gtin"] == gtin
    raise "conteggio integrati errato (#{n})" unless n == 2
    nuovo, = DataManager.integra_backup_preferiti({ "favorites" => [{ "id" => "b", "description" => "brisee stesa 230g" }] }, salvato)
    raise "un preferito cancellato dall'app deve sparire" unless nuovo["favorites"].map { |f| f["id"] } == ["b"]
    puts "integra_preferito_test OK"
  end
end
