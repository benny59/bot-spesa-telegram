#!/usr/bin/env ruby
# db.rb
require 'sqlite3'

DB = SQLite3::Database.new("spesa.db")
DB.results_as_hash = true

# tabelle core (create se non esistono)
DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS gruppi (
    id INTEGER PRIMARY KEY,
    chat_id INTEGER UNIQUE,
    nome TEXT,
    creato_da INTEGER,
    data_creazione DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL

DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS items (
    id INTEGER PRIMARY KEY,
    nome TEXT,
    comprato INTEGER DEFAULT 0,
    gruppo_id INTEGER,
    creato_da INTEGER,
    data_creazione DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY(gruppo_id) REFERENCES gruppi(id)
  );
SQL

DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS membri_gruppi (
    user_id INTEGER,
    gruppo_id INTEGER,
    is_admin INTEGER DEFAULT 0,
    PRIMARY KEY (user_id, gruppo_id),
    FOREIGN KEY(gruppo_id) REFERENCES gruppi(id)
  );
SQL

DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
  );
SQL

DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS pending_actions (
    chat_id INTEGER PRIMARY KEY,
    action TEXT,
    gruppo_id INTEGER
  );
SQL
DB.execute <<-SQL
  CREATE TABLE IF NOT EXISTS user_names (
    user_id INTEGER PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
SQL
