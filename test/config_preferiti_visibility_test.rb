require "tmpdir"

Dir.mktmpdir("config-preferiti-visibility-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)
    require File.expand_path("../models/lista", __dir__)

    user_id = 42
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (0, 0, ?, ?)",
      [user_id, "riparare motoretta"]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (0, 0, ?, ?)",
      [user_id, Lista::CONFIG_PREFERITI_PREFISSO]
    )
    config_legacy_id = DB.last_insert_row_id
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (0, 0, ?, ?)",
      [user_id, Lista::CONFIG_PREFERITI_NOME]
    )

    nomi_telegram = DataManager.prendi_articoli_ordinati(0, 0).map { |item| item["nome"] }
    raise "La configurazione preferiti legacy e' visibile su Telegram" if nomi_telegram.include?(Lista::CONFIG_PREFERITI_PREFISSO)
    raise "La configurazione preferiti corrente e' visibile su Telegram" if nomi_telegram.include?(Lista::CONFIG_PREFERITI_NOME)
    raise "L'articolo personale e' stato filtrato" unless nomi_telegram == ["riparare motoretta"]

    configurazioni_salvate = DB.get_first_value(
      "SELECT COUNT(*) FROM items WHERE nome LIKE ?",
      ["#{Lista::CONFIG_PREFERITI_PREFISSO}%"]
    ).to_i
    raise "I record di configurazione sono stati rimossi" unless configurazioni_salvate == 2

    raise "Il record tecnico risulta cancellabile" if DataManager.soft_delete_item(config_legacy_id)
    deleted = DB.get_first_value("SELECT deleted FROM items WHERE id = ?", [config_legacy_id]).to_i
    raise "Il record tecnico e' stato marcato come cancellato" unless deleted == 0
  end
end

puts "OK: configurazione preferiti nascosta dalla lista Telegram"