require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    require File.expand_path("../api_server", __dir__)
    require File.expand_path("../utils/keyboard_generator", __dir__)

    DB.execute <<-SQL
      CREATE TABLE IF NOT EXISTS memberships (
        user_id INTEGER,
        gruppo_id INTEGER,
        last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, gruppo_id)
      );
    SQL

    deleted_item = {
      "id" => 17,
      "gruppo_id" => 4,
      "topic_id" => 0,
      "nome" => "Miele al mercato",
      "link_url" => "",
      "comprato" => "",
      "buyer_initials" => "",
      "creato_da" => 42,
      "user_initials" => "MB",
      "creato_il" => "2026-08-22 10:00:00",
      "ha_foto" => 0,
      "deleted" => 1,
      "nome_topic" => ""
    }

    android_item = serializza_item(deleted_item.merge("categoria_id" => 7, "categoria_nome" => "Verdura"), nome_gruppo: "Omegna")
    raise "Android /lista/tutti perde il flag deleted" unless android_item[:deleted] == true
    raise "Android /lista/tutti perde la categoria" unless android_item[:categoria_id] == 7 && android_item[:categoria_nome] == "Verdura"

    DB.execute("INSERT OR IGNORE INTO memberships (user_id, gruppo_id, last_seen) VALUES (?, ?, CURRENT_TIMESTAMP)", [42, 4])
    DB.execute("INSERT OR IGNORE INTO memberships (user_id, gruppo_id, last_seen) VALUES (?, ?, CURRENT_TIMESTAMP)", [42, 5])
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted, comprato, disponibile) VALUES (4, 0, ?, ?, 0, '', 1)",
      [42, "Gruppo 4 attivo"]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted, comprato, disponibile) VALUES (4, 0, ?, ?, 0, ?, 1)",
      [42, "Gruppo 4 comprato", 42]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted, comprato, disponibile) VALUES (5, 0, ?, ?, 0, '', 1)",
      [42, "Gruppo 5 attivo"]
    )
    names = DataManager.prendi_tutto_ovunque(42).map { |item| item["nome"] }
    raise "Vista globale non raggruppa per contesto: #{names.inspect}" unless names == ["Gruppo 4 attivo", "Gruppo 4 comprato", "Gruppo 5 attivo"]

    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted) VALUES (0, 0, ?, ?, 0)",
      [42, "Personale mio"]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted) VALUES (0, 0, ?, ?, 0)",
      [99, "Personale altrui"]
    )
    nomi_personali = DataManager.prendi_articoli_per_storico(0, 0, 42, true).map { |item| item["nome"] }
    raise "Tutti gli articoli espone liste personali altrui" unless nomi_personali == ["Personale mio"]

    DataManager.singleton_class.send(:define_method, :recupera_nomi_contesto) do |_g_id, _t_id|
      { nome: "Omegna", topic: "Generale" }
    end
    DataManager.singleton_class.send(:define_method, :prendi_articoli_per_storico) do |_g_id, _t_id, _user_id, _show_all|
      [deleted_item.merge("autore_init" => "MB", "buyer_init" => "", "ha_foto_reale" => 0)]
    end

    markup = KeyboardGenerator.markup_lista_globale(
      42,
      [{ "gruppo_id" => 4, "topic_id" => 0 }],
      { "db_id" => 4, "topic_id" => 0 },
      0,
      1,
      true,
      42
    )
    labels = markup.inline_keyboard.flatten.map(&:text)
    deleted_label = labels.find { |label| label.include?("Miele al mercato") }

    raise "Telegram Tutti gli articoli perde l'indicazione deleted" unless deleted_label&.include?("~~")
    raise "Telegram Tutti gli articoli non offre il ripristino" unless deleted_label&.include?("↩️")

    puts "Deleted item coerente tra Android e Telegram."

    unavailable_item = {
      "id" => 18,
      "gruppo_id" => 4,
      "topic_id" => 0,
      "nome" => "Pane fuori stagione",
      "link_url" => "",
      "comprato" => "",
      "buyer_initials" => "",
      "creato_da" => 42,
      "user_initials" => "MB",
      "creato_il" => "2026-08-22 11:00:00",
      "ha_foto" => 0,
      "deleted" => 0,
      "disponibile" => 0,
      "nome_topic" => ""
    }

    android_unavailable = serializza_item(unavailable_item, nome_gruppo: "Omegna")
    raise "Android /lista/tutti perde il flag disponibile" unless android_unavailable[:disponibile] == false

    DataManager.singleton_class.send(:define_method, :prendi_articoli_per_storico) do |_g_id, _t_id, _user_id, _show_all|
      [unavailable_item.merge("autore_init" => "MB", "buyer_init" => "", "ha_foto_reale" => 0)]
    end

    markup = KeyboardGenerator.markup_lista_globale(
      42,
      [{ "gruppo_id" => 4, "topic_id" => 0 }],
      { "db_id" => 4, "topic_id" => 0 },
      0,
      1,
      true,
      42
    )
    unavailable_label = markup.inline_keyboard.flatten.map(&:text).find { |label| label.include?("Pane fuori stagione") }
    raise "Telegram Tutti gli articoli perde l'indicazione non disponibile" unless unavailable_label&.include?("❌") || unavailable_label&.include?("~~")

    puts "Unavailable item coerente tra Android e Telegram."

    DB.execute("DELETE FROM categorie WHERE LOWER(nome) IN ('casa', 'verdura', 'frutta')")
    DB.execute("INSERT OR IGNORE INTO categorie (id, nome, gruppo_id, topic_id) VALUES (23, 'Verdura', 4, 0)")
    DB.execute("INSERT OR IGNORE INTO categorie (id, nome, gruppo_id, topic_id) VALUES (24, 'Frutta', 4, 0)")
    DB.execute("INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, last_categoria_id, ultima_aggiunta, updated_at) VALUES (4, 0, 'Mela', 2, 24, datetime('now'), datetime('now'))")

    DB.execute("INSERT OR IGNORE INTO categorie (gruppo_id, topic_id, nome) VALUES (4, 0, 'frutta')")
    DB.execute("INSERT OR IGNORE INTO categorie (gruppo_id, topic_id, nome) VALUES (4, 0, 'Frutta')")
    canonical_frutta = DataManager.categoria_canonica(4, 0, 'frutta')
    raise "La categoria canonica in DB sporco non è coerente: #{canonical_frutta.inspect}" unless canonical_frutta && canonical_frutta["nome"] == "Frutta"
    canonical_verdura = DataManager.categoria_preferita_db(4, 0, 'verdura')
    raise "La categoria preferita in DB sporco non è coerente: #{canonical_verdura.inspect}" unless canonical_verdura && canonical_verdura["nome"] == "Verdura"

    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "Mela", topic_id: 0, split_items: false)
    new_item = DB.get_first_row("SELECT categoria_id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = LOWER(?)", [4, 0, "Mela"])
    raise "Fallback categoria da storico non applicato" unless new_item && new_item["categoria_id"].to_i == 24

    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "Mela & Frutta", topic_id: 0, split_items: false)
    explicit_item = DB.get_first_row("SELECT i.nome, i.categoria_id, c.nome AS categoria_nome FROM items i LEFT JOIN categorie c ON c.id = i.categoria_id WHERE i.gruppo_id = ? AND i.topic_id = ? AND LOWER(i.nome) = LOWER(?) ORDER BY i.id DESC LIMIT 1", [4, 0, "Mela"])
    raise "Categoria esplicita temporanea non deve essere sovrascritta dal default storico" unless explicit_item && explicit_item["categoria_nome"] == "Frutta" && explicit_item["categoria_id"].to_i > 0

    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "Insalata di riso & gastronomia", topic_id: 0, split_items: false)
    item_temp = DB.get_first_row("SELECT nome, categoria_id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = LOWER(?) ORDER BY id DESC LIMIT 1", [4, 0, "Insalata di riso & gastronomia"])
    raise "Categoria temporanea non deve essere scritta nel nome item" unless item_temp && item_temp["nome"] == "Insalata di riso & gastronomia" && item_temp["categoria_id"].to_i == 0
    parsed = DataManager.parse_nome_categoria(item_temp["nome"], nil, nil, 4, 0)
    raise "Parsing categoria temporanea non applicato" unless parsed[:nome] == "Insalata di riso" && parsed[:categoria_id].nil? && parsed[:categoria_temporanea] == "Gastronomia"
    serialized = serializza_item(item_temp.merge("categoria_nome" => ""), nome_gruppo: "Omegna")
    raise "Serializzazione categoria temporanea non applicata" unless serialized[:nome] == "Insalata di riso" && serialized[:categoria_nome] == "Gastronomia"
    raise "Categoria temporanea non deve essere persistita nel catalogo" unless DB.get_first_value("SELECT COUNT(*) FROM categorie WHERE LOWER(nome) = LOWER(?)", ["Gastronomia"]).to_i == 0

    DB.execute("INSERT OR IGNORE INTO categorie (id, nome, gruppo_id, topic_id) VALUES (23, 'Verdura', 4, 0)")
    DB.execute("INSERT OR IGNORE INTO categorie (id, nome, gruppo_id, topic_id) VALUES (24, 'Frutta', 4, 0)")
    DB.execute("INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, last_categoria_id, ultima_aggiunta, updated_at) VALUES (4, 0, 'Insalata', 3, 23, datetime('now'), datetime('now'))")
    DB.execute("INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, last_categoria_id, ultima_aggiunta, updated_at) VALUES (4, 0, 'Mele', 4, 24, datetime('now'), datetime('now'))")
    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "Insalata trevigiana", topic_id: 0, split_items: false)
    fallback_insalata = DB.get_first_row("SELECT categoria_id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = LOWER(?) ORDER BY id DESC LIMIT 1", [4, 0, "Insalata trevigiana"])
    raise "Fallback storico per nome composto non applicato: insalata trevigiana" unless fallback_insalata && fallback_insalata["categoria_id"].to_i == 23
    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "4 mele", topic_id: 0, split_items: false)
    fallback_mele = DB.get_first_row("SELECT categoria_id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = LOWER(?) ORDER BY id DESC LIMIT 1", [4, 0, "4 mele"])
    raise "Fallback storico per nome con prefisso numerico non applicato: 4 mele" unless fallback_mele && fallback_mele["categoria_id"].to_i == 24

    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "Latte [YUKA_LINK] https://example.com/milk", topic_id: 0, link_url: "https://example.com/milk", split_items: false)
    item_with_marker = DB.get_first_row("SELECT nome, link_url FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = LOWER(?)", [4, 0, "Latte"])
    raise "Marker [YUKA_LINK] non filtrato dal nome dell'item" unless item_with_marker && item_with_marker["nome"] == "Latte" && item_with_marker["link_url"] == "https://example.com/milk"

    parsed_manual = DataManager.parse_nome_categoria("viti & ferramenta", nil, nil, 4, 0)
    raise "Categoria effimera nel nome item non valutata" unless parsed_manual[:nome] == "viti" && parsed_manual[:categoria_id].nil? && parsed_manual[:categoria_temporanea] == "Ferramenta"

    DataManager.singleton_class.send(:define_method, :prendi_articoli_per_storico) do |g_id, t_id, user_id, show_all|
      DataManager.articoli_attivi(g_id, t_id, user_id, show_all: show_all && g_id != 0)
    end

    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, deleted, comprato, disponibile) VALUES (4, 0, 42, 'Insalata di riso & gastronomia', 0, '', 1)")
    telegram_markup = KeyboardGenerator.markup_lista_globale(
      42,
      [{ "gruppo_id" => 4, "topic_id" => 0 }],
      { "db_id" => 4, "topic_id" => 0 },
      0,
      1,
      false,
      42
    )
    telegram_labels = telegram_markup.inline_keyboard.flatten.map(&:text)
    raise "Telegram mostra il nome grezzo con categoria effimera" if telegram_labels.any? { |label| label.include?("Insalata di riso & gastronomia") }
    raise "Telegram non mostra il nome parsato della categoria effimera" unless telegram_labels.any? { |label| label.include?("Insalata di riso") }

    DB.execute("DELETE FROM categorie WHERE LOWER(nome) IN ('casa', 'verdura', 'frutta')")
    DB.execute("INSERT INTO categorie (id, nome, gruppo_id, topic_id) VALUES (200, 'Casa', 4, 0)")
    DB.execute("INSERT INTO categorie (id, nome, gruppo_id, topic_id) VALUES (201, 'Verdura', 4, 0)")
    DB.execute("INSERT INTO categorie (id, nome, gruppo_id, topic_id) VALUES (202, 'Frutta', 4, 0)")
    DB.execute("INSERT OR IGNORE INTO categorie (gruppo_id, topic_id, nome) VALUES (4, 0, 'frutta')")
    DataManager.aggiungi_articoli(gruppo_id: 4, user_id: 42, items_text: "rotolone & casa, insalata, pomodorini & verdura, mele, arance & frutta", topic_id: 0, split_items: true)
    item_map = DB.execute("SELECT nome, categoria_id FROM items WHERE gruppo_id = ? AND topic_id = ? AND nome IN ('rotolone','insalata','pomodorini','mele','arance') ORDER BY id", [4, 0]).each_with_object({}) { |row, h| h[row["nome"]] = row["categoria_id"].to_i }
    raise "Categoria associativa non applicata" unless item_map == { "rotolone" => 200, "insalata" => 0, "pomodorini" => 201, "mele" => 0, "arance" => 202 }

    DB.execute("DELETE FROM categorie")
    DB.execute("INSERT INTO categorie (gruppo_id, topic_id, nome) VALUES (99, 0, 'Frutta')")
    DB.execute("INSERT INTO categorie (gruppo_id, topic_id, nome) VALUES (99, 0, 'frutta')")
    DB.execute("INSERT INTO categorie (gruppo_id, topic_id, nome) VALUES (42, 0, 'verdura')")
    DB.execute("INSERT INTO categorie (gruppo_id, topic_id, nome) VALUES (42, 0, 'ferramenta')")

    android_categories = DataManager.categorie_per_android(99, 0)
    labels = android_categories.map { |row| [row[:nome], row[:effimera]] }
    canonical_ok = labels.any? { |nome, effimera| nome == "Frutta" && effimera == false }
    effimera_ok = labels.any? { |nome, effimera| nome == "ferramenta" && effimera == true }
    raise "Catalogo categorie Android deve distinguere canoniche da effimere: #{android_categories.inspect}" unless canonical_ok && effimera_ok

    assegnabili = DataManager.categorie_assegnabili(99, 0)
    raise "Le categorie effimere non devono essere assegnabili: #{assegnabili.inspect}" unless assegnabili.all? { |row| row[:effimera] == false } && assegnabili.none? { |row| row[:nome].downcase == "ferramenta" }

    DB.execute("INSERT INTO categorie (gruppo_id, topic_id, nome) VALUES (4, 0, 'gastronomia')")
    categoria_temp_id = DB.get_first_value("SELECT id FROM categorie WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? LIMIT 1", [4, 0, 'gastronomia'])
    DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, categoria_id, deleted, comprato, disponibile) VALUES (4, 0, 42, 'Pasta gourmet', ?, 0, '', 1)", [categoria_temp_id])
    item_id = DB.get_first_value("SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? LIMIT 1", [4, 0, 'pasta gourmet'])
    DataManager.rimuovi_da_lista(item_id)
    raise "La categoria temporanea deve sparire dopo la cancellazione definitiva dell'ultimo item: #{DB.execute('SELECT id, nome FROM categorie WHERE gruppo_id = 4 AND topic_id = 0').inspect}" unless DB.get_first_value("SELECT COUNT(*) FROM categorie WHERE id = ?", [categoria_temp_id]).to_i == 0

    puts "Fallback categoria da storico coerente."
  end
end
