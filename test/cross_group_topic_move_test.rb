# frozen_string_literal: true

require "json"
require "rack/mock"
require_relative "../db"
require_relative "../models/lista"
require_relative "../api_server"

DB.execute("DELETE FROM item_images")
DB.execute("DELETE FROM items")
DB.execute("DELETE FROM topics")
DB.execute("DELETE FROM gruppi")
DB.execute("DELETE FROM memberships")

DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (1, 'A', -1001, 42)")
DB.execute("INSERT INTO gruppi (id, nome, chat_id, creato_da) VALUES (2, 'B', -2002, 42)")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-1001, 0, 'Principale')")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-2002, 0, 'Principale')")
DB.execute("INSERT INTO topics (chat_id, topic_id, nome) VALUES (-2002, 7, 'Frutta')")
DB.execute("INSERT INTO memberships (user_id, gruppo_id, last_seen) VALUES (?, ?, CURRENT_TIMESTAMP)", [42, 2])

# cross-group/topic move legacy behavior
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, ?, ?, ?)", [1, 0, 42, "Pane"])
item_id = DB.get_first_value("SELECT id FROM items WHERE nome = 'Pane' LIMIT 1")
raise "item non creatato" if item_id.to_i <= 0
ok = Lista.sposta_topic(item_id, 2, 7)
raise "lo spostamento cross-group/topic fallito" unless ok
row = DB.get_first_row("SELECT gruppo_id, topic_id FROM items WHERE id = ?", [item_id])
raise "il gruppo non è stato aggiornato" unless row["gruppo_id"].to_i == 2
raise "il topic non è stato aggiornato" unless row["topic_id"].to_i == 7

# move to personal list must be accepted by API route for group owner
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, ?, ?, ?)", [2, 7, 42, "Frutta da personale"])
personal_item_id = DB.get_first_value("SELECT id FROM items WHERE nome = 'Frutta da personale' LIMIT 1")
response = Rack::MockRequest.new(Sinatra::Application).patch(
  "/lista/#{personal_item_id}/topic",
  input: { gruppo_id: 0, topic_id: 0, user_id: 42 }.to_json,
  "CONTENT_TYPE" => "application/json"
)
raise "lo spostamento da gruppo a lista personale è stato bloccato" unless response.status == 200

# move from personal list to group must be accepted by API route
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, ?, ?, ?)", [0, 0, 42, "Personale da gruppo"])
from_personal_id = DB.get_first_value("SELECT id FROM items WHERE nome = 'Personale da gruppo' LIMIT 1")
response = Rack::MockRequest.new(Sinatra::Application).patch(
  "/lista/#{from_personal_id}/topic",
  input: { gruppo_id: 2, topic_id: 7, user_id: 42 }.to_json,
  "CONTENT_TYPE" => "application/json"
)
raise "lo spostamento da lista personale a gruppo è stato bloccato" unless response.status == 200

# display order should be: normal -> checked -> unavailable -> deleted
DB.execute("DELETE FROM items")
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, disponibile, deleted) VALUES (1, 0, 42, 'Normale', '', 1, 0)")
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, disponibile, deleted) VALUES (1, 0, 42, 'Checked', '42', 1, 0)")
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, disponibile, deleted) VALUES (1, 0, 42, 'Non disponibile', '', 0, 0)")
DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome, comprato, disponibile, deleted) VALUES (1, 0, 42, 'Cancellato', '', 1, 1)")
ordered = DataManager.articoli_attivi(1, 0, nil, show_all: true).map { |row| row["nome"] }
expected_order = ["Normale", "Checked", "Non disponibile", "Cancellato"]
raise "l'ordine di visualizzazione non rispetta la priorità normale > checked > non disponibili > cancellati" unless ordered == expected_order

puts "cross-group/topic move ok"
