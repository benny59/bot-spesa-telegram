require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    require File.expand_path("../api_server", __dir__)
    require File.expand_path("../utils/keyboard_generator", __dir__)

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

    android_item = serializza_item(deleted_item, nome_gruppo: "Omegna")
    raise "Android /lista/tutti perde il flag deleted" unless android_item[:deleted] == true

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
    raise "Telegram Tutti gli articoli perde l'indicazione non disponibile" unless unavailable_label&.include?("🚫")

    puts "Unavailable item coerente tra Android e Telegram."
  end
end
