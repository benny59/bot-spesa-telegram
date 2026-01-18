# db.rb
require "sqlite3"

DB_PATH = "spesa.db"

def init_db
  db = SQLite3::Database.new(DB_PATH)
  db.results_as_hash = true

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

  # db.rb
  db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS topics (
    chat_id INTEGER,
    topic_id INTEGER,
    nome TEXT,
    PRIMARY KEY (chat_id, topic_id)
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

  # 🔧 items → aggiunto topic_id
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      gruppo_id INTEGER,
      topic_id INTEGER DEFAULT 0,
      creato_da INTEGER,
      nome TEXT,
      comprato TEXT DEFAULT '',
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (gruppo_id) REFERENCES gruppi (id)
    );
  SQL

  # 🔧 pending_actions → aggiunto topic_id
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS pending_actions (
      chat_id INTEGER,
      topic_id INTEGER DEFAULT 0,
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

  # 🔗 memberships -> lega gli utenti ai gruppi (scoperta tramite /private, items o cleanup)
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS memberships (
      user_id INTEGER,
      gruppo_id INTEGER,
      last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (user_id, gruppo_id),
      FOREIGN KEY (gruppo_id) REFERENCES gruppi (id) ON DELETE CASCADE
    );
  SQL

  # Indice per velocizzare il recupero dei gruppi di un utente
  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_memberships_user 
    ON memberships (user_id);
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
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      formato TEXT DEFAULT 'code128'
    );
  SQL

  # 🔧 storico_articoli → aggiunto topic_id
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS storico_articoli (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome TEXT NOT NULL,
      gruppo_id INTEGER NOT NULL,
      topic_id INTEGER DEFAULT 0,
      conteggio INTEGER DEFAULT 0,
      ultima_aggiunta DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(nome, gruppo_id, topic_id),
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

  # 🔧 indici aggiornati
  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_items_gruppo_topic
    ON items (gruppo_id, topic_id);
  SQL

  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_pending_actions_chat_topic
    ON pending_actions (chat_id, topic_id);
  SQL

  db.execute <<-SQL
    CREATE INDEX IF NOT EXISTS idx_storico_gruppo_topic
    ON storico_articoli (gruppo_id, topic_id, conteggio DESC, ultima_aggiunta DESC);
  SQL

  puts "✅ Database inizializzato / aggiornato (supporto topic_id)"
  db
end

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
