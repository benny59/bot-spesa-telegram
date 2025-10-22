# db.rb
require "sqlite3"

DB_PATH = "spesa.db"

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
      initials TEXT,
      aggiornato_il DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      gruppo_id INTEGER,
      creato_da INTEGER,
      nome TEXT,
      comprato TEXT DEFAULT '', -- ✅ già corretto: stringa vuota = non comprato
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
    initiator_id INTEGER,
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
      view_mode TEXT DEFAULT 'compact',
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS carte_fedelta (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      nome TEXT NOT NULL,
      codice TEXT NOT NULL,
      immagine_path TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS storico_articoli (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      gruppo_id INTEGER NOT NULL,
      conteggio INTEGER DEFAULT 0,
      ultima_aggiunta DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(nome, gruppo_id),
      FOREIGN KEY (gruppo_id) REFERENCES gruppi(id) ON DELETE CASCADE
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS gruppo_carte_collegamenti (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      gruppo_id INTEGER NOT NULL,
      carta_id INTEGER NOT NULL,
      added_by INTEGER NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (gruppo_id) REFERENCES gruppi(id) ON DELETE CASCADE,
      FOREIGN KEY (carta_id) REFERENCES carte_fedelta(id) ON DELETE CASCADE,
      UNIQUE(gruppo_id, carta_id)
    );
  SQL

  # Crea indici per performance
  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_storico_gruppo_conteggio 
    ON storico_articoli (gruppo_id, conteggio DESC, ultima_aggiunta DESC);
  SQL

  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_storico_gruppo_nome 
    ON storico_articoli (gruppo_id, nome);
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
