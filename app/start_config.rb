#!/usr/bin/env ruby
# start_config.rb

require 'sqlite3'
require_relative '../services/openfoodfacts_client'
require_relative '../services/barcode_scanner'

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

# Assicura l'esistenza della tabella products con una nuova colonna per le caratteristiche
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    barcode TEXT,
    characteristics TEXT
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

# Inizializza il client Open Food Facts
openfoodfacts_client = OpenFoodFactsClient.new

# Inizializza il barcode scanner
barcode_scanner = BarcodeScanner.new

puts "📦 Pronto per scansionare i codici a barre dei prodotti."