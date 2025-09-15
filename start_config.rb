#!/usr/bin/env ruby
# setup_config.rb

require 'sqlite3'

DB_FILE = "spesa.db"

unless File.exist?(DB_FILE)
  puts "❌ Il file #{DB_FILE} non esiste. Avvia prima bot_spesa.rb per creare il database."
  exit
end

db = SQLite3::Database.new(DB_FILE)

# Assicura l'esistenza della tabella config
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
  );
SQL

def upsert(db, key, value)
  db.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [key, value])
end

puts "⚙️ Configurazione bot"
print "👉 Inserisci il TOKEN di Telegram: "
token = STDIN.gets.strip
upsert(db, "token", token)

# In futuro puoi aggiungere altre configurazioni (es. proxy, default chat, ecc.)
puts "✅ Configurazione salvata in tabella config."

