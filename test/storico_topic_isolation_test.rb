# frozen_string_literal: true

require "tmpdir"

Dir.mktmpdir("storico-topic-test") do |directory|
  Dir.chdir(directory) do
    require File.expand_path("../db", __dir__)

    DB.execute("INSERT INTO gruppi (nome, chat_id, creato_da) VALUES (?, ?, ?)", ["Gruppo test", -100_001, 42])
    gruppo_id = DB.last_insert_row_id

    DataManager.upsert_storico_articolo(gruppo_id, 10, "Pane")
    DataManager.upsert_storico_articolo(gruppo_id, 20, "Pane")
    DB.execute(
      "INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio) VALUES (?, ?, ?, ?)",
      [gruppo_id, 10, "pane", 2]
    )

    DataManager.pulisci_storico_capitalize

    rows = DB.execute(
      "SELECT topic_id, nome, conteggio FROM storico_articoli WHERE gruppo_id = ? ORDER BY topic_id",
      [gruppo_id]
    )

    raise "lo storico deve restare separato per topic: #{rows.inspect}" unless rows.map { |row| row["topic_id"] } == [10, 20]
    raise "i duplicati del topic 10 non sono stati consolidati" unless rows[0]["conteggio"].to_i == 3
    raise "il conteggio del topic 20 e' stato alterato" unless rows[1]["conteggio"].to_i == 1
  end
end

puts "storico topic isolation ok"