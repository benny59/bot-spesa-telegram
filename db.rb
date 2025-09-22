# db.rb
require 'sqlite3'

DB_PATH = 'spesa.db'

def init_db
  db = SQLite3::Database.new(DB_PATH)
  db.results_as_hash = true

  # Crea tutte le tabelle con lo schema corretto
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS config (
      key TEXT PRIMARY KEY,
      value TEXT
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS gruppi (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT,
      creato_da INTEGER,
      chat_id INTEGER UNIQUE,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS user_names (
      user_id INTEGER PRIMARY KEY,
      first_name TEXT,
      last_name TEXT,
      initials TEXT,  -- COLONNA AGGIUNTA
      aggiornato_il DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    gruppo_id INTEGER,
    creato_da INTEGER,
    nome TEXT,
    comprato TEXT DEFAULT '', -- ✅ ora è TEXT, stringa vuota = non comprato
    creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (gruppo_id) REFERENCES gruppi (id)
  );
SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS pending_actions (
      chat_id INTEGER,
      action TEXT,
      gruppo_id INTEGER,
      item_id INTEGER,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS item_images (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER,
      file_id TEXT,
      file_unique_id TEXT,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (item_id) REFERENCES items (id)
    );
  SQL
  
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS whitelist (
    user_id INTEGER PRIMARY KEY,
    username TEXT,
    full_name TEXT,
    added_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL
  
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS pending_requests (
    user_id INTEGER PRIMARY KEY,
    username TEXT,
    full_name TEXT,
    requested_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL

db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS user_preferences (
    user_id INTEGER PRIMARY KEY,
    view_mode TEXT DEFAULT 'compact', -- 'compact' o 'text_only'
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL

  puts "✅ Database inizializzato con schema corretto"
  db
end

# Metodi di utilità per il database
class DB
  def self.execute(*args)
    db.execute(*args)
  end

  def self.get_first_row(*args)
    db.get_first_row(*args)
  end

  def self.get_first_value(*args)
    db.get_first_value(*args)
  end

  def self.db
    @db ||= init_db
  end
end
