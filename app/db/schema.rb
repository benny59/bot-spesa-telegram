# schema.rb

# This file defines the current schema of the database, outlining the structure of tables and their relationships.

require 'sqlite3'

DB_FILE = "spesa.db"

db = SQLite3::Database.new(DB_FILE)

# Define the schema for the products table
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    barcode TEXT UNIQUE,
    characteristics TEXT
  );
SQL

# Define the schema for the config table
db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS config (
    key TEXT PRIMARY KEY,
    value TEXT
  );
SQL

# Additional tables can be defined here as needed.