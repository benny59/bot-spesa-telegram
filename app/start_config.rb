# start_config.rb
require 'sqlite3'

DB_FILE = File.expand_path("../spesa.db", __dir__)
db = SQLite3::Database.new(DB_FILE)

# Crea tabella config
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
  );
SQL

# Crea tabella products
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT,
    barcode TEXT UNIQUE,
    price REAL,
    quantity INTEGER DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
SQL

puts "✅ Database inizializzato in #{DB_FILE}"

# Inserisco un valore di esempio se non esiste già
existing = db.execute("SELECT 1 FROM config WHERE key = 'token' LIMIT 1")
if existing.empty?
  db.execute("INSERT INTO config (key, value) VALUES (?, ?)", ['token', 'INSERISCI_IL_TUO_TOKEN'])
  puts "⚠️ Inserito token di esempio, ricordati di aggiornarlo."
end

