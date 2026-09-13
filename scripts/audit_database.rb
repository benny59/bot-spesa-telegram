#!/usr/bin/env ruby
# frozen_string_literal: true

require "sqlite3"

EXPECTED_TABLES = {
  "config" => %w[key value],
  "gruppi" => %w[id nome creato_da chat_id notifiche_operazioni creato_il],
  "topics" => %w[chat_id topic_id nome],
  "items" => %w[id gruppo_id topic_id creato_da nome link_url categoria_id comprato deleted disponibile creato_il],
  "item_images" => %w[id item_id file_id file_unique_id creato_il],
  "memberships" => %w[user_id gruppo_id last_seen],
  "categorie" => %w[id gruppo_id topic_id nome],
  "user_names" => %w[user_id first_name last_name initials aggiornato_il],
  "user_preferences" => %w[user_id view_mode updated_at],
  "whitelist" => %w[user_id username full_name added_at],
  "pending_requests" => %w[user_id username full_name requested_at],
  "storico_articoli" => %w[id gruppo_id topic_id nome link_url conteggio creato_da comprato_da last_categoria_id last_file_id last_file_unique_id metadata_json ultima_aggiunta created_at updated_at],
  "categoria_stats" => %w[id gruppo_id topic_id categoria_id categoria_nome tipo conteggio ultima_aggiunta created_at updated_at],
  "pending_actions" => %w[chat_id topic_id action gruppo_id initiator_id item_id creato_il],
  "carte_fedelta" => %w[id user_id nome codice formato immagine_path created_at],
  "gruppo_carte_collegamenti" => %w[id gruppo_id carta_id added_by created_at],
  "liste_modello" => %w[id gruppo_id topic_id nome items_raw creato_da creato_il aggiornato_il],
  "link_pins" => %w[pin user_id first_name created_at]
}.freeze

EXPECTED_PRIMARY_KEYS = {
  "config" => %w[key],
  "gruppi" => %w[id],
  "topics" => %w[chat_id topic_id],
  "items" => %w[id],
  "item_images" => %w[id],
  "memberships" => %w[user_id gruppo_id],
  "categorie" => %w[id],
  "user_names" => %w[user_id],
  "user_preferences" => %w[user_id],
  "whitelist" => %w[user_id],
  "pending_requests" => %w[user_id],
  "storico_articoli" => %w[id],
  "categoria_stats" => %w[id],
  "pending_actions" => %w[chat_id topic_id],
  "carte_fedelta" => %w[id],
  "gruppo_carte_collegamenti" => %w[id],
  "liste_modello" => %w[id],
  "link_pins" => %w[pin]
}.freeze

EXPECTED_UNIQUE_KEYS = {
  "gruppi" => [%w[chat_id]],
  "categorie" => [%w[gruppo_id topic_id nome]],
  "storico_articoli" => [%w[nome gruppo_id topic_id]],
  "categoria_stats" => [
    %w[gruppo_id topic_id categoria_id tipo],
    %w[gruppo_id topic_id categoria_nome tipo]
  ],
  "gruppo_carte_collegamenti" => [%w[gruppo_id carta_id]],
  "liste_modello" => [%w[gruppo_id topic_id nome]]
}.freeze

ORPHAN_CHECKS = [
  ["items.gruppo_id -> gruppi.id", "items", "id", "gruppo_id != 0 AND NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = items.gruppo_id)"],
  ["items.categoria_id -> categorie.id", "items", "id", "categoria_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categorie c WHERE c.id = items.categoria_id)"],
  ["item_images.item_id -> items.id", "item_images", "id", "item_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM items i WHERE i.id = item_images.item_id)"],
  ["memberships.gruppo_id -> gruppi.id", "memberships", "rowid", "NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = memberships.gruppo_id)"],
  ["categorie.gruppo_id -> gruppi.id", "categorie", "id", "gruppo_id != 0 AND NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = categorie.gruppo_id)"],
  ["storico_articoli.gruppo_id -> gruppi.id", "storico_articoli", "id", "gruppo_id != 0 AND NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = storico_articoli.gruppo_id)"],
  ["storico_articoli.last_categoria_id -> categorie.id", "storico_articoli", "id", "last_categoria_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categorie c WHERE c.id = storico_articoli.last_categoria_id)"],
  ["categoria_stats.gruppo_id -> gruppi.id", "categoria_stats", "id", "gruppo_id != 0 AND NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = categoria_stats.gruppo_id)"],
  ["categoria_stats.categoria_id -> categorie.id", "categoria_stats", "id", "categoria_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM categorie c WHERE c.id = categoria_stats.categoria_id)"],
  ["gruppo_carte_collegamenti.gruppo_id -> gruppi.id", "gruppo_carte_collegamenti", "id", "NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = gruppo_carte_collegamenti.gruppo_id)"],
  ["gruppo_carte_collegamenti.carta_id -> carte_fedelta.id", "gruppo_carte_collegamenti", "id", "NOT EXISTS (SELECT 1 FROM carte_fedelta c WHERE c.id = gruppo_carte_collegamenti.carta_id)"],
  ["liste_modello.gruppo_id -> gruppi.id", "liste_modello", "id", "gruppo_id != 0 AND NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = liste_modello.gruppo_id)"],
  ["group_cards.gruppo_id -> gruppi.id", "group_cards", "id", "NOT EXISTS (SELECT 1 FROM gruppi g WHERE g.id = group_cards.gruppo_id)"]
].freeze

DUPLICATE_CHECKS = [
  ["storico per gruppo/topic/nome", "storico_articoli", "gruppo_id, COALESCE(topic_id, 0), LOWER(TRIM(nome))"],
  ["item attivi per gruppo/topic/nome", "items", "gruppo_id, COALESCE(topic_id, 0), LOWER(TRIM(nome))", "deleted = 0"],
  ["membership utente/gruppo", "memberships", "user_id, gruppo_id"],
  ["collegamenti gruppo/carta", "gruppo_carte_collegamenti", "gruppo_id, carta_id"],
  ["azioni pendenti chat/topic", "pending_actions", "chat_id, COALESCE(topic_id, 0)"]
].freeze

def quote_identifier(identifier)
  %Q{"#{identifier.to_s.gsub('"', '""')}"}
end

def table_exists?(db, table)
  !db.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", table).nil?
end

def table_columns(db, table)
  db.execute("PRAGMA table_info(#{quote_identifier(table)})")
end

def primary_key(db, table)
  table_columns(db, table).select { |column| column["pk"].to_i.positive? }
                          .sort_by { |column| column["pk"].to_i }
                          .map { |column| column["name"] }
end

def unique_keys(db, table)
  db.execute("PRAGMA index_list(#{quote_identifier(table)})")
    .select { |index| index["unique"].to_i == 1 && index["origin"] != "pk" }
    .map do |index|
      db.execute("PRAGMA index_info(#{quote_identifier(index['name'])})")
        .sort_by { |column| column["seqno"].to_i }
        .map { |column| column["name"] }
    end
end

def ids_for(db, table, id_column, condition)
  db.execute("SELECT #{quote_identifier(id_column)} AS record_id FROM #{quote_identifier(table)} WHERE #{condition} ORDER BY 1")
    .map { |row| row["record_id"] }
end

def sql_literal(value)
  return value.to_i.to_s if value.is_a?(Integer)

  "'#{value.to_s.gsub("'", "''")}'"
end

def print_sql(title, statements)
  puts "\n-- #{title}"
  puts "BEGIN IMMEDIATE;"
  statements.each { |statement| puts "#{statement};" }
  puts "COMMIT;"
end

def print_schema_migrations(schema_issues)
  if schema_issues.any? { |issue| issue.start_with?("storico_articoli: UNIQUE") }
    puts <<~SQL

      -- MIGRAZIONE storico_articoli: separa lo storico per topic.
      -- Eseguire solo dopo avere risolto gli orfani riportati sopra.
      BEGIN IMMEDIATE;
      CREATE TABLE storico_articoli_migrazione (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gruppo_id INTEGER NOT NULL,
        topic_id INTEGER NOT NULL DEFAULT 0,
        nome TEXT NOT NULL,
        link_url TEXT,
        conteggio INTEGER DEFAULT 0,
        creato_da INTEGER,
        comprato_da INTEGER,
        last_categoria_id INTEGER,
        last_file_id TEXT,
        last_file_unique_id TEXT,
        metadata_json TEXT,
        ultima_aggiunta DATETIME,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(nome, gruppo_id, topic_id),
        FOREIGN KEY (gruppo_id) REFERENCES gruppi(id) ON DELETE CASCADE,
        FOREIGN KEY (last_categoria_id) REFERENCES categorie(id)
      );
      INSERT INTO storico_articoli_migrazione (
        id, gruppo_id, topic_id, nome, link_url, conteggio, creato_da, comprato_da,
        last_categoria_id, last_file_id, last_file_unique_id, metadata_json,
        ultima_aggiunta, created_at, updated_at
      )
      SELECT id, gruppo_id, COALESCE(topic_id, 0), nome, link_url, conteggio,
             creato_da, comprato_da, last_categoria_id, last_file_id,
             last_file_unique_id, metadata_json, ultima_aggiunta, created_at, updated_at
      FROM storico_articoli;
      DROP TABLE storico_articoli;
      ALTER TABLE storico_articoli_migrazione RENAME TO storico_articoli;
      CREATE INDEX idx_storico_gruppo_topic ON storico_articoli (gruppo_id, topic_id, conteggio DESC, ultima_aggiunta DESC);
      CREATE INDEX idx_storico_nome_gruppo ON storico_articoli (nome, gruppo_id, topic_id);
      CREATE INDEX idx_storico_last_categoria ON storico_articoli (gruppo_id, topic_id, LOWER(nome), last_categoria_id);
      COMMIT;
    SQL
  end

  return unless schema_issues.any? { |issue| issue.start_with?("pending_actions: PK=") }

  puts <<~SQL

    -- MIGRAZIONE pending_actions: una sola azione per chat/topic.
    -- Il controllo duplicati deve risultare [OK] prima dell'esecuzione.
    BEGIN IMMEDIATE;
    CREATE TABLE pending_actions_migrazione (
      chat_id INTEGER,
      topic_id INTEGER NOT NULL DEFAULT 0,
      action TEXT,
      gruppo_id INTEGER DEFAULT 0,
      initiator_id INTEGER,
      item_id INTEGER,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (chat_id, topic_id)
    );
    INSERT INTO pending_actions_migrazione
      (chat_id, topic_id, action, gruppo_id, initiator_id, item_id, creato_il)
    SELECT chat_id, COALESCE(topic_id, 0), action, gruppo_id, initiator_id, item_id, creato_il
    FROM pending_actions;
    DROP TABLE pending_actions;
    ALTER TABLE pending_actions_migrazione RENAME TO pending_actions;
    CREATE INDEX idx_pending_actions_chat_topic ON pending_actions (chat_id, topic_id);
    COMMIT;
  SQL
end

db_path = File.expand_path(ARGV.fetch(0, "spesa.db"))
abort "Database non trovato: #{db_path}" unless File.file?(db_path)

db = SQLite3::Database.new(db_path, flags: SQLite3::Constants::Open::READONLY)
db.results_as_hash = true
db.execute("PRAGMA query_only = ON")

puts "AUDIT DATABASE (sola lettura)"
puts "Database: #{db_path}"
puts "SQLite: #{SQLite3::SQLITE_VERSION}"
puts "Integrity check: #{db.get_first_value('PRAGMA integrity_check')}"
puts "Query only: #{db.get_first_value('PRAGMA query_only') == 1 ? 'attivo' : 'NON ATTIVO'}"

schema_issues = []
puts "\n== 1. Struttura reale e attesa =="
EXPECTED_TABLES.each do |table, expected_columns|
  unless table_exists?(db, table)
    schema_issues << "tabella mancante: #{table}"
    puts "[ERRORE] #{table}: tabella mancante"
    next
  end

  actual_columns = table_columns(db, table).map { |column| column["name"] }
  missing_columns = expected_columns - actual_columns
  extra_columns = actual_columns - expected_columns
  expected_pk = EXPECTED_PRIMARY_KEYS.fetch(table, [])
  actual_pk = primary_key(db, table)
  expected_unique = EXPECTED_UNIQUE_KEYS.fetch(table, [])
  actual_unique = unique_keys(db, table)

  issues = []
  issues << "colonne mancanti=#{missing_columns.join(',')}" if missing_columns.any?
  issues << "PK=#{actual_pk.inspect}, attesa=#{expected_pk.inspect}" if actual_pk != expected_pk
  missing_unique = expected_unique.reject { |key| actual_unique.include?(key) }
  issues << "UNIQUE mancanti=#{missing_unique.inspect}" if missing_unique.any?

  if issues.empty?
    suffix = extra_columns.empty? ? "" : " (colonne aggiuntive: #{extra_columns.join(',')})"
    puts "[OK] #{table}#{suffix}"
  else
    schema_issues.concat(issues.map { |issue| "#{table}: #{issue}" })
    puts "[DIFF] #{table}: #{issues.join('; ')}"
  end
end

legacy_tables = db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
                  .map { |row| row["name"] } - EXPECTED_TABLES.keys
puts legacy_tables.empty? ? "[OK] Nessuna tabella legacy" : "[INFO] Tabelle non previste: #{legacy_tables.join(', ')}"

puts "\n== 2. Duplicati =="
duplicate_count = 0
DUPLICATE_CHECKS.each do |label, table, key, condition|
  next unless table_exists?(db, table)

  where = condition ? "WHERE #{condition}" : ""
  groups = db.execute("SELECT #{key}, COUNT(*) AS record_count FROM #{quote_identifier(table)} #{where} GROUP BY #{key} HAVING COUNT(*) > 1")
  duplicate_count += groups.length
  puts groups.empty? ? "[OK] #{label}" : "[ATTENZIONE] #{label}: #{groups.length} gruppi duplicati"
  groups.each { |group| puts "  #{group.reject { |column, _| column.is_a?(Integer) }.inspect}" }
end

puts "\n== 3. Catene rotte e record orfani =="
orphan_fixes = []
orphan_fix_keys = {}
orphan_count = 0
ORPHAN_CHECKS.each do |label, table, id_column, condition|
  next unless table_exists?(db, table)

  ids = ids_for(db, table, id_column, condition)
  if ids.empty?
    puts "[OK] #{label}"
    next
  end

  orphan_count += ids.length
  puts "[ORFANI] #{label}: #{ids.length} record; ID=#{ids.join(',')}"
  literals = ids.map { |id| sql_literal(id) }.join(", ")
  if label == "items.categoria_id -> categorie.id"
    orphan_fixes << "UPDATE items SET categoria_id = NULL WHERE id IN (#{literals})"
  elsif label == "storico_articoli.last_categoria_id -> categorie.id"
    orphan_fixes << "UPDATE storico_articoli SET last_categoria_id = NULL WHERE id IN (#{literals})"
  else
    key = [table, id_column]
    orphan_fix_keys[key] ||= []
    orphan_fix_keys[key].concat(ids)
  end
end

orphan_fix_keys.each do |(table, id_column), ids|
  literals = ids.uniq.sort.map { |id| sql_literal(id) }.join(", ")
  orphan_fixes << "DELETE FROM #{quote_identifier(table)} WHERE #{quote_identifier(id_column)} IN (#{literals})"
end

foreign_key_findings = db.execute("PRAGMA foreign_key_check")
personal_sentinel_findings, foreign_key_violations = foreign_key_findings.partition do |violation|
  next false unless violation["parent"] == "gruppi" && %w[items storico_articoli].include?(violation["table"])

  db.get_first_value(
    "SELECT gruppo_id FROM #{quote_identifier(violation['table'])} WHERE rowid = ?",
    violation["rowid"]
  ).to_i.zero?
end

unless personal_sentinel_findings.empty?
  puts "[INFO] FK verso gruppi con gruppo_id=0: #{personal_sentinel_findings.length} record personali ammessi dall'app"
end

if foreign_key_violations.empty?
  puts "[OK] PRAGMA foreign_key_check"
else
  puts "[ATTENZIONE] PRAGMA foreign_key_check: #{foreign_key_violations.length} violazioni dichiarate"
  foreign_key_violations.each do |violation|
    puts "  tabella=#{violation['table']} rowid=#{violation['rowid']} parent=#{violation['parent']} fk=#{violation['fkid']}"
  end
end

puts "\n== 4. SQL proposto (NON eseguito) =="
if schema_issues.empty?
  puts "-- Schema conforme: nessuna migrazione strutturale proposta."
else
  puts "-- Differenze schema rilevate:"
  schema_issues.each { |issue| puts "-- - #{issue}" }
  puts "-- Le modifiche a PK/UNIQUE richiedono la ricostruzione della tabella."
  puts "-- Validare sempre le query seguenti su una copia prima dell'esecuzione in produzione."
end

if orphan_fixes.empty?
  puts "-- Nessuna query di rimozione orfani necessaria."
else
  print_sql("Rimozione puntuale degli orfani rilevati; verificare gli ID prima dell'uso", orphan_fixes)
end

print_schema_migrations(schema_issues) unless schema_issues.empty?

if table_exists?(db, "group_cards")
  puts <<~SQL

    -- group_cards e' una tabella legacy con dati incorporati, non un semplice doppione.
    -- Non viene proposta una migrazione automatica: confrontare user_id/nome/codice/formato
    -- con carte_fedelta e creare i collegamenti mancanti prima di eliminare record legacy.
  SQL
end

puts "\nRiepilogo: differenze_schema=#{schema_issues.length}, gruppi_duplicati=#{duplicate_count}, orfani=#{orphan_count}"
puts "Nessuna modifica eseguita."
db.close