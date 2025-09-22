#!/usr/bin/env ruby
# setup_db.rb

require 'sqlite3'
require_relative '../app/db/migrate/001_add_characteristics_to_products'

DB_FILE = "spesa.db"

unless File.exist?(DB_FILE)
  puts "❌ Il file #{DB_FILE} non esiste. Avvia prima bot_spesa.rb per creare il database."
  exit
end

db = SQLite3::Database.new(DB_FILE)

# Assicura l'esistenza della tabella products
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    barcode TEXT,
    characteristics TEXT
  );
SQL

# Esegui la migrazione per aggiungere la colonna characteristics
AddCharacteristicsToProducts.new.change(db)

puts "✅ Database configurato e migrazioni eseguite."