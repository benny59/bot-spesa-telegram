require "tmpdir"

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    require File.expand_path("../db", __dir__)

    user_id = 1
    other_user_id = 2
    DB.execute <<-SQL
      CREATE TABLE memberships (
        user_id INTEGER NOT NULL,
        gruppo_id INTEGER NOT NULL
      )
    SQL
    group_id = DB.execute(
      "INSERT INTO gruppi (nome, chat_id) VALUES (?, ?)",
      ["Test", -1001]
    ).then { DB.last_insert_row_id }
    other_group_id = DB.execute(
      "INSERT INTO gruppi (nome, chat_id) VALUES (?, ?)",
      ["Altro", -1002]
    ).then { DB.last_insert_row_id }
    DB.execute(
      "INSERT INTO memberships (user_id, gruppo_id) VALUES (?, ?)",
      [user_id, group_id]
    )
    DB.execute(
      "INSERT INTO memberships (user_id, gruppo_id) VALUES (?, ?)",
      [other_user_id, other_group_id]
    )

    DB.execute(
      "INSERT INTO categorie (gruppo_id, topic_id, nome, creato_da) VALUES (?, ?, ?, ?)",
      [group_id, 0, "Verdura", user_id]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, deleted) VALUES (?, ?, ?, ?, ?, ?)",
      [group_id, 0, user_id, "Detersivo & pulizia", "", 0]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, deleted) VALUES (?, ?, ?, ?, ?, ?)",
      [group_id, 0, user_id, "Sapone & bagno", user_id.to_s, 0]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, deleted) VALUES (?, ?, ?, ?, ?, ?)",
      [group_id, 0, user_id, "Vecchio & garage", "", 1]
    )
    DB.execute(
      "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, deleted) VALUES (?, ?, ?, ?, ?, ?)",
      [other_group_id, 0, other_user_id, "Altro & ufficio", "", 0]
    )
    DB.execute(
      "INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, ultima_aggiunta, updated_at) VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
      [group_id, 0, "Storico & cantina"]
    )
    DB.execute(
      "INSERT INTO categoria_stats (gruppo_id, topic_id, categoria_nome, tipo, conteggio, ultima_aggiunta, updated_at) VALUES (?, ?, ?, 'effimera', 1, datetime('now'), datetime('now'))",
      [group_id, 0, "Cantina"]
    )

    categorie = DataManager.categorie_assegnabili(group_id, 0, user_id)
    nomi = categorie.map { |categoria| categoria[:nome] }
    effimere = categorie.select { |categoria| categoria[:effimera] }.map { |categoria| categoria[:nome] }

    raise "Categoria canonica mancante: #{nomi.inspect}" unless nomi.include?("Verdura")
    raise "Effimere attive errate: #{effimere.inspect}" unless effimere.sort == ["Bagno", "Pulizia"]
    raise "Effimera da item cancellato inclusa" if nomi.include?("Garage")
    raise "Effimera da storico/statistiche inclusa" if nomi.include?("Cantina")
    raise "Effimera di altro gruppo inclusa" if nomi.include?("Ufficio")

    DataManager.esegui_scopetta(group_id, 0)
    effimere_dopo_scopetta = DataManager.categorie_assegnabili(group_id, 0, user_id)
                                      .select { |categoria| categoria[:effimera] }
                                      .map { |categoria| categoria[:nome] }
    raise "Scopetta non ha rimosso effimera senza item attivi: #{effimere_dopo_scopetta.inspect}" unless effimere_dopo_scopetta == ["Pulizia"]

    puts "Categorie assegnabili: canoniche più effimere attive, senza storico."
  end
end