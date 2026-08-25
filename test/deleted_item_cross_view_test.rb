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
  end
end
