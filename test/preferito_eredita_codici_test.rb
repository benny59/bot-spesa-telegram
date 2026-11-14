# frozen_string_literal: true

require "tmpdir"

Dir.mktmpdir("preferito-eredita-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)

    DB.execute("INSERT INTO gruppi (nome, chat_id, creato_da) VALUES (?, ?, ?)", ["G", -100_003, 42])
    g = DB.last_insert_row_id
    uid = 42
    gtin = "8076809513722"
    link = "https://app.yuka.io/yogurt-1"
    salva = lambda do |favs|
      DB.execute("DELETE FROM items WHERE nome = ?", [DataManager::CONFIG_PREFERITI_NOME])
      DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, link_url) VALUES (0, 0, ?, ?, ?)",
                 [uid, DataManager::CONFIG_PREFERITI_NOME, JSON.generate(favorites: favs)])
    end
    aggiungi = lambda do |testo, **opz|
      id = DataManager.aggiungi_articoli(gruppo_id: g, user_id: uid, items_text: testo, topic_id: 0, split_items: false, **opz).first
      DB.get_first_row("SELECT nome, gtin, link_url FROM items WHERE id = ?", [id])
    end

    # 1) nome identico (anche in maiuscole diverse) a UN preferito con codici -> li eredita
    salva.call([{ "id" => "a", "description" => "Yogurt greco", "gtin" => gtin, "yukaLink" => link }])
    r = aggiungi.call("yogurt GRECO")
    raise "gtin non ereditato: #{r.inspect}" unless r["gtin"] == gtin && r["link_url"] == link
    raise "prodotto non registrato col nome del preferito" unless DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [gtin]) == "yogurt GRECO" || DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [gtin]).to_s.downcase == "yogurt greco"

    # 2) nome diverso (generico "yogurt") -> niente
    r = aggiungi.call("yogurt")
    raise "nome non identico non deve ereditare" unless r["gtin"].nil? && r["link_url"].nil?

    # 3) due preferiti con lo stesso nome e prodotti diversi -> ambiguo, niente
    salva.call([{ "id" => "a", "description" => "Yogurt greco", "gtin" => gtin },
                { "id" => "b", "description" => "Yogurt greco", "gtin" => "8000300155877" }])
    r = aggiungi.call("Yogurt greco")
    # l'articolo del punto 1 è ancora in lista (stesso nome): esiste già -> non si sovrascrive il suo gtin
    raise "gtin esistente sovrascritto: #{r.inspect}" unless r["gtin"] == gtin
    DB.execute("DELETE FROM items WHERE gruppo_id = ?", [g])
    r = aggiungi.call("Yogurt greco")
    raise "caso ambiguo: non deve assegnare codici (#{r.inspect})" unless r["gtin"].nil?

    # 4) un preferito generico (senza codici) con lo stesso nome non rende ambiguo quello specifico
    salva.call([{ "id" => "a", "description" => "Yogurt greco", "gtin" => gtin }, { "id" => "c", "description" => "yogurt greco" }])
    DB.execute("DELETE FROM items WHERE gruppo_id = ?", [g])
    r = aggiungi.call("Yogurt greco")
    raise "il generico non deve bloccare lo specifico" unless r["gtin"] == gtin

    # 5) gtin passato esplicitamente vince sul preferito
    DB.execute("DELETE FROM items WHERE gruppo_id = ?", [g])
    r = aggiungi.call("Yogurt greco", gtin: "8000300155877")
    raise "il gtin esplicito deve vincere" unless r["gtin"] == "8000300155877"

    # 6) articolo già in lista senza codici: li riceve dal preferito
    DB.execute("DELETE FROM items WHERE gruppo_id = ?", [g])
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, 0, ?, 'Yogurt greco')", [g, uid])
    r = aggiungi.call("Yogurt greco")
    raise "articolo esistente senza gtin non arricchito" unless r["gtin"] == gtin
    puts "preferito_eredita_codici_test OK"
  end
end
