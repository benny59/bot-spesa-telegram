# frozen_string_literal: true

require_relative "../db"
require_relative "../models/lista"

DB.execute("DELETE FROM item_images")
DB.execute("DELETE FROM items")
DB.execute("DELETE FROM topics")
DB.execute("DELETE FROM gruppi")

DB.execute("INSERT INTO gruppi (id, nome, chat_id) VALUES (1, 'A', -1001)")
DB.execute("INSERT INTO gruppi (id, nome, chat_id) VALUES (2, 'B', -2002)")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-1001, 0, 'Principale')")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-2002, 0, 'Principale')")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-2002, 7, 'Frutta')")

DB.execute(
  "INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, ?, ?, ?)",
  [1, 0, 42, "Pane"]
)

item_id = DB.get_first_value("SELECT id FROM items WHERE nome = 'Pane' LIMIT 1")
raise "item non creato" if item_id.to_i <= 0

ok = Lista.sposta_topic(item_id, 2, 7)
raise "lo spostamento cross-group/topic fallito" unless ok

row = DB.get_first_row("SELECT gruppo_id, topic_id FROM items WHERE id = ?", [item_id])
raise "il gruppo non è stato aggiornato" unless row["gruppo_id"].to_i == 2
raise "il topic non è stato aggiornato" unless row["topic_id"].to_i == 7

puts "cross-group/topic move ok"
