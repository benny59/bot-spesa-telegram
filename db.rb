# db.rb
require "sqlite3"
require "json"

DB_PATH = "spesa.db"

# ==============================================================================
# INIZIALIZZAZIONE SCHEMA (STRUTTURA ESISTENTE - NON TOCCARE)
# ==============================================================================
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

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS pending_actions (
      chat_id INTEGER,
      topic_id INTEGER DEFAULT 0,
      action TEXT,
      gruppo_id INTEGER DEFAULT 0,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (chat_id, topic_id)
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS whitelist (
      user_id INTEGER PRIMARY KEY,
      added_by INTEGER,
      added_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS carte_fedelta (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      nome TEXT,
      codice TEXT,
      formato TEXT,
      creato_il DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS storico_articoli (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      gruppo_id INTEGER,
      topic_id INTEGER DEFAULT 0,
      nome TEXT,
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

  # Indici per performance
  db.execute "CREATE INDEX IF NOT EXISTS idx_items_gruppo_topic ON items (gruppo_id, topic_id);"
  db.execute "CREATE INDEX IF NOT EXISTS idx_pending_actions_chat_topic ON pending_actions (chat_id, topic_id);"
  db.execute "CREATE INDEX IF NOT EXISTS idx_storico_gruppo_topic ON storico_articoli (gruppo_id, topic_id, conteggio DESC, ultima_aggiunta DESC);"

  puts "✅ [DB] Database inizializzato correttamente."
  db
end

# Oggetto globale accessibile da tutta l'applicazione
DB = init_db

# ==============================================================================
# CLASSE DATA_MANAGER (MONITOR ARCHITETTURALE)
# ==============================================================================
class DataManager
  def self.setup_database
    puts "[DATA_MONITOR] 🔍 Verifica integrità database..."
    # Chiamiamo la funzione init_db che abbiamo già nel file
    init_db
  end

  # ----------------------------------------------------------------------------
  # GESTIONE CARRELLO (Soluzione B)
  # ----------------------------------------------------------------------------

  # Spunta un articolo (mette nel carrello)
  def self.spunta_articolo(item_id, user_name)
    puts "[DATA_MONITOR] 🛒 Articolo #{item_id} messo nel carrello da #{user_name}"
    DB.execute("UPDATE items SET comprato = ? WHERE id = ?", [user_name, item_id])
  end

  # Ripristina un articolo (toglie dal carrello)
  def self.despunta_articolo(item_id)
    puts "[DATA_MONITOR] 🔄 Articolo #{item_id} rimosso dal carrello"
    DB.execute("UPDATE items SET comprato = '' WHERE id = ?", [item_id])
  end

  def self.rimuovi_item_diretto(item_id)
    puts "[DATA_MONITOR] 🗑️ Rimozione forzata item ID: #{item_id} (nessuna modifica storico)"
    DB.execute("DELETE FROM items WHERE id = ?", [item_id])
  end

  def self.get_topic_name(g_id, t_id)
    return "Personale" if g_id.to_i == 0
    return "Generale" if t_id.to_i == 0

    # Dobbiamo usare l'ID database per trovare il chat_id reale
    real_chat_id = DB.get_first_value("SELECT chat_id FROM gruppi WHERE id = ?", [g_id])

    if real_chat_id
      row = DB.get_first_row("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [real_chat_id, t_id])
      return row["nome"].to_s if row && row["nome"] && !row["nome"].to_s.strip.empty?
    end

    "#{t_id}" # Torna 'sperimentale' se lo trova, altrimenti '2'
  end

  # ----------------------------------------------------------------------------
  # LA SCOPETTA (Cleanup & Storico)
  # ----------------------------------------------------------------------------
  # Cancella gli articoli comprati e aggiorna il conteggio nello storico
  def self.esegui_scopetta(gruppo_id, topic_id = 0)
    puts "[DATA_MONITOR] 🧹 Avvio scopetta selettiva per G:#{gruppo_id} T:#{topic_id}"

    comprati = DB.execute(
      "SELECT nome FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''",
      [gruppo_id, topic_id]
    )
    return if comprati.empty?

    DB.transaction do
      comprati.each do |item|
        nome_norm = item["nome"].to_s.strip

        # 1. Vediamo se esiste già (senza fidarci dei vincoli)
        esistente = DB.get_first_row(
          "SELECT id, conteggio FROM storico_articoli WHERE LOWER(nome) = LOWER(?) AND gruppo_id = ? AND topic_id = ?",
          [nome_norm, gruppo_id, topic_id]
        )

        if esistente
          # 2. Se esiste, facciamo UPDATE
          DB.execute(
            "UPDATE storico_articoli SET conteggio = conteggio + 1, ultima_aggiunta = datetime('now'), updated_at = datetime('now') WHERE id = ?",
            [esistente["id"]]
          )
        else
          # 3. Se non esiste, facciamo INSERT semplice
          # Usiamo 'INSERT OR IGNORE' così se proprio c'è un indice fantasma non crasha comunque
          DB.execute(
            "INSERT OR IGNORE INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, ultima_aggiunta, updated_at) VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
            [gruppo_id, topic_id, nome_norm]
          )
        end
      end

      # 4. Pulizia finale
      DB.execute("DELETE FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''", [gruppo_id, topic_id])
    end
    puts "[DATA_MONITOR] ✅ Scopetta completata."
  rescue => e
    puts "❌ [DATA_ERROR] Errore: #{e.message}"
  end
  # ----------------------------------------------------------------------------
  # REGISTRAZIONE UTENTE (WHITELIST)
  # ----------------------------------------------------------------------------
  def self.registra_utente(user_id, first_name, last_name)
    # Calcoliamo le iniziali per comodità di visualizzazione futura
    initials = "#{first_name.to_s[0]}#{last_name.to_s[0]}".upcase

    DB.execute(
      "INSERT OR REPLACE INTO user_names (user_id, first_name, last_name, initials, aggiornato_il) 
       VALUES (?, ?, ?, ?, datetime('now'))",
      [user_id, first_name, last_name, initials]
    )

    # Assicuriamoci che sia anche nella whitelist base
    DB.execute("INSERT OR IGNORE INTO whitelist (user_id, added_at) VALUES (?, datetime('now'))", [user_id])
  rescue => e
    puts "❌ [DATA_ERROR] Errore registrazione utente: #{e.message}"
  end

  # ----------------------------------------------------------------------------
  # RECUPERO AZIONE PENDENTE
  # ----------------------------------------------------------------------------
  def self.ottieni_pending(chat_id, topic_id = 0)
    # Cerchiamo l'ultima azione salvata per questa specifica chat/reparto
    DB.get_first_row(
      "SELECT action, gruppo_id FROM pending_actions WHERE chat_id = ? AND topic_id = ?",
      [chat_id, topic_id]
    )
  rescue => e
    puts "❌ [DATA_ERROR] Errore recupero pending: #{e.message}"
    nil
  end

  # ----------------------------------------------------------------------------
  # PILASTRO '+': AGGIUNTA ARTICOLI
  # ----------------------------------------------------------------------------
  def self.aggiungi_articoli(gruppo_id:, user_id:, items_text:, topic_id: 0)
    puts "[DATA_MONITOR] 📝 Scrittura Articoli -> G:#{gruppo_id} | T:#{topic_id} | U:#{user_id}"

    nomi = items_text.split(",").map(&:strip).reject(&:empty?)
    return [] if nomi.empty?
    salvati = 0 # <--- FONDAMENTALE: Inizializza a zero
    DB.transaction do
      nomi.each do |nome|
        esiste = DB.get_first_value("SELECT COUNT(*) FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND comprato = ''", [gruppo_id, topic_id, nome.downcase])
        next if esiste > 0

        DB.execute(
          "INSERT INTO items (gruppo_id, topic_id, creato_da, nome, creato_il) VALUES (?, ?, ?, ?, datetime('now'))",
          [gruppo_id, topic_id, user_id, nome]
        )
        salvati += 1
      end
    end

    puts "[DATA_MONITOR] ✅ Successo: #{nomi.size} articoli salvati."
    nomi
  rescue => e
    puts "❌ [DATA_ERROR] Errore in aggiungi_articoli: #{e.message}"
    raise e
  end

  def self.genera_header_contesto(g_id, t_id)
    if g_id == 0
      "🏠 Lista Personale"
    else
      # Recupera il nome del gruppo
      g_nome = DB.get_first_value("SELECT nome FROM gruppi WHERE id = ?", [g_id]) || "Gruppo #{g_id}"
      # Usa il tuo metodo get_topic_name per risolvere "Generale" o "sperimentale"
      nome_t = self.get_topic_name(g_id, t_id)
      "🎯 #{g_nome}: Lista #{nome_t}"
    end
  end

  def self.prendi_per_contesto(g_id, t_id)
    # Usiamo solo items e gruppi (che esiste sicuramente come FK)
    query = <<-SQL
    SELECT i.*, g.nome as nome_gruppo
    FROM items i
    LEFT JOIN gruppi g ON i.gruppo_id = g.id
    WHERE i.gruppo_id = ? AND i.topic_id = ?
    ORDER BY i.creato_il DESC
  SQL
    DB.execute(query, [g_id, t_id])
  end

  def self.prendi_miei_ovunque(u_id)
    query = <<-SQL
    SELECT i.*, g.nome as nome_gruppo
    FROM items i
    LEFT JOIN gruppi g ON i.gruppo_id = g.id
    WHERE i.creato_da = ? 
    AND (i.gruppo_id = 0 OR i.gruppo_id IN (SELECT gruppo_id FROM memberships WHERE user_id = ?))
    ORDER BY i.gruppo_id, i.creato_il DESC
  SQL
    DB.execute(query, [u_id, u_id])
  end

  def self.prendi_tutto_ovunque(u_id)
    query = <<-SQL
    SELECT i.*, g.nome as nome_gruppo
    FROM items i
    LEFT JOIN gruppi g ON i.gruppo_id = g.id
    WHERE i.gruppo_id IN (SELECT gruppo_id FROM memberships WHERE user_id = ?)
       OR (i.gruppo_id = 0 AND i.creato_da = ?)
    ORDER BY i.gruppo_id, i.creato_il DESC
  SQL
    DB.execute(query, [u_id, u_id])
  end

  def self.aggiorna_membership(u_id, g_id)
    # Usiamo 'last_seen' come definito nel tuo CREATE TABLE
    query = <<-SQL
    INSERT INTO memberships (user_id, gruppo_id, last_seen)
    VALUES (?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(user_id, gruppo_id) DO UPDATE SET
    last_seen = CURRENT_TIMESTAMP
  SQL

    begin
      DB.execute(query, [u_id, g_id])
      # puts "[DB] Membership aggiornata: U:#{u_id} G:#{g_id}"
    rescue SQLite3::Exception => e
      puts "❌ [DB ERROR] Errore aggiorna_membership: #{e.message}"
    end
  end
  def self.prendi_destinazioni_censite(user_id)
    # Usiamo 'g_nome' anche qui per coerenza
    destinazioni = [{ "chat_id" => 0, "topic_id" => 0, "nome" => "👤 Lista Personale", "g_nome" => "Privata" }]

    sql = <<-SQL
    SELECT g.id, g.chat_id, t.topic_id, t.nome as t_nome, g.nome as g_nome
    FROM memberships m
    JOIN gruppi g ON m.gruppo_id = g.id
    JOIN topics t ON g.chat_id = t.chat_id
    WHERE m.user_id = ?
  SQL

    res = DB.execute(sql, [user_id])
    res.each do |r|
      # Recupero nome reale del topic (riga 173)
      t_label = r["t_nome"].to_s.strip.empty? ? self.nome_topic(r["chat_id"], r["topic_id"]) : r["t_nome"]

      destinazioni << {
        "chat_id" => r["id"],
        "topic_id" => r["topic_id"],
        "nome" => "👥 #{r["g_nome"]}: #{t_label}", # Icona singola risolta
        "g_nome" => r["g_nome"], # Salviamo il nome del gruppo separato per l'intestazione
      }
    end
    p destinazioni
    destinazioni
  end

  def self.prendi_articoli_ordinati(gruppo_id, topic_id)
    # Usiamo una JOIN per prendere il conteggio dallo storico mentre carichiamo gli items
    sql = <<-SQL
    SELECT i.*, IFNULL(s.conteggio, 0) as volte
    FROM items i
    LEFT JOIN storico_articoli s ON LOWER(i.nome) = LOWER(s.nome) 
      AND i.gruppo_id = s.gruppo_id 
      AND i.topic_id = s.topic_id
    WHERE i.gruppo_id = ? AND i.topic_id = ?
    ORDER BY 
      CASE WHEN i.comprato != '' THEN 1 ELSE 0 END ASC, 
      i.creato_il DESC
  SQL
    DB.execute(sql, [gruppo_id, topic_id])
  end
  # ----------------------------------------------------------------------------
  # PILASTRO '?': STORICO E RICERCA
  # ----------------------------------------------------------------------------
  def self.ricerca_storico(gruppo_id:, topic_id: 0, query: nil)
    puts "[DATA_MONITOR] 🔍 Lettura Storico -> G:#{gruppo_id} | T:#{topic_id} (Query: #{query || "Tutti"})"

    sql = "SELECT nome, conteggio, ultima_aggiunta FROM storico_articoli WHERE gruppo_id = ? AND topic_id = ?"
    params = [gruppo_id, topic_id]

    if query
      sql += " AND nome LIKE ?"
      params << "%#{query}%"
    end

    sql += " ORDER BY conteggio DESC, ultima_aggiunta DESC LIMIT 20"
    DB.execute(sql, params)
  end

  # ----------------------------------------------------------------------------
  # GESTIONE CONTESTO E CONFIGURAZIONE
  # ----------------------------------------------------------------------------
  def self.carica_config_utente(user_id)
    row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{user_id}"])
    row ? JSON.parse(row["value"]) : nil
  rescue => e
    puts "❌ [DATA_ERROR] Errore parsing config user #{user_id}: #{e.message}"
    nil
  end

  def self.salva_config_utente(user_id, config_hash)
    puts "[DATA_MONITOR] ⚙️ Update Context Utente: #{user_id}"
    DB.execute(
      "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
      ["context:#{user_id}", config_hash.to_json]
    )
  end

  # ----------------------------------------------------------------------------
  # GESTIONE AZIONI IN SOSPESO (PENDING ACTIONS)
  # ----------------------------------------------------------------------------
  def self.set_pending(chat_id:, topic_id:, action:, gruppo_id: 0)
    puts "[DATA_MONITOR] ⏳ PendingAction -> Chat:#{chat_id} | Azione:#{action}"
    DB.execute(
      "INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id) VALUES (?, ?, ?, ?)",
      [chat_id, topic_id, action, gruppo_id]
    )
  end

  def self.clear_pending(chat_id:, topic_id: 0)
    DB.execute("DELETE FROM pending_actions WHERE chat_id = ? AND topic_id = ?", [chat_id, topic_id])
    puts "[DATA_MONITOR] 🧹 Pending rimosse per Chat:#{chat_id} Topic:#{topic_id}"
  end

  def self.salva_nuova_carta(u_id, nome, codice, formato, img_path)
    DB.execute(
      "INSERT INTO carte_fedelta (user_id, nome, codice, formato, immagine_path) VALUES (?, ?, ?, ?, ?)",
      [u_id, nome, codice, formato.to_s, img_path]
    )
  end

  # Recupero dettaglio: la colonna restituita sarà 'tipo'
  def self.prendi_dettaglio_carta(carta_id, u_id)
    DB.get_first_row("SELECT * FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, u_id])
  end

  # Recupero lista
  def self.prendi_carte_utente(u_id)
    DB.execute("SELECT id, nome FROM carte_fedelta WHERE user_id = ? ORDER BY LOWER(nome) ASC", [u_id])
  end

  # In db.rb (DataManager)
  def self.elimina_carta(carta_id, u_id)
    DB.execute("DELETE FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, u_id])
  end
end
