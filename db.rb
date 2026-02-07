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
  # Aggiungi questo dentro init_db in db.rb, prima della chiusura del metodo
  db.execute <<-SQL
  CREATE TABLE IF NOT EXISTS item_images (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    item_id INTEGER,
    file_id TEXT,
    file_unique_id TEXT,
    creato_il DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items (id) ON DELETE CASCADE
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
    creato_da INTEGER,       -- <--- AGGIUNTO
    comprato_da INTEGER,     -- <--- AGGIUNTO
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
  db.execute "CREATE INDEX IF NOT EXISTS idx_storico_nome_gruppo ON storico_articoli (nome, gruppo_id, topic_id);"

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

  def self.comprato?(item_id)
    res = DB.get_first_value("SELECT comprato FROM items WHERE id = ?", [item_id])
    res && res != ""
  end

  # In db.rb (classe DataManager)
  def self.recupera_nomi_contesto(g_id, t_id)
    return { nome: "Privata", topic: "Lista Personale" } if g_id == 0

    # Recupero info Gruppo
    gruppo = DB.get_first_row("SELECT nome, chat_id FROM gruppi WHERE id = ?", [g_id])
    return { nome: "Gruppo #{g_id}", topic: "" } unless gruppo

    g_nome = gruppo["nome"]
    c_id = gruppo["chat_id"]

    # Recupero nome Topic (anche per 0)
    t_nome = DB.get_first_value("SELECT nome FROM topics WHERE chat_id = ? AND topic_id = ?", [c_id, t_id])

    { nome: g_nome, topic: t_nome || (t_id == 0 ? "Generale" : t_id.to_s) }
  end

  def self.rimuovi_item_diretto(item_id)
    puts "[DATA_MONITOR] 🗑️ Rimozione forzata item ID: #{item_id} (inclusa pulizia foto)"

    # 1. Rimuoviamo prima le foto associate all'articolo
    DB.execute("DELETE FROM item_images WHERE item_id = ?", [item_id.to_i])

    # 2. Poi rimuoviamo l'articolo stesso
    DB.execute("DELETE FROM items WHERE id = ?", [item_id.to_i])
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
    puts "[DATA_MONITOR] 🧹 Scopetta: elaborazione diciture esatte per G:#{gruppo_id}"

    comprati = DB.execute(
      "SELECT nome, creato_da, comprato FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''",
      [gruppo_id, topic_id]
    )
    return if comprati.empty?

    DB.transaction do
      comprati.each do |item|
        nome_esatto = item["nome"].to_s.strip # Puliamo solo gli spazi esterni
        c_da = item["creato_da"]
        comp_da = item["comprato"]

        # Ricerca ESATTA (Rimosso LOWER)
        esistente = DB.get_first_row(
          "SELECT id FROM storico_articoli WHERE nome = ? AND gruppo_id = ? AND topic_id = ?",
          [nome_esatto, gruppo_id, topic_id]
        )

        if esistente
          DB.execute(
            "UPDATE storico_articoli SET 
           conteggio = conteggio + 1, 
           creato_da = ?, 
           comprato_da = ?, 
           updated_at = datetime('now') 
           WHERE id = ?",
            [c_da, comp_da, esistente["id"]]
          )
        else
          DB.execute(
            "INSERT OR IGNORE INTO storico_articoli 
           (gruppo_id, topic_id, nome, conteggio, creato_da, comprato_da, ultima_aggiunta) 
           VALUES (?, ?, ?, 1, ?, ?, datetime('now'))",
            [gruppo_id, topic_id, nome_esatto, c_da, comp_da]
          )
        end
      end
      DB.execute(
        "DELETE FROM item_images WHERE item_id IN (
          SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''
        )",
        [gruppo_id, topic_id]
      )

      DB.execute("DELETE FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''", [gruppo_id, topic_id])
    end
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
  # PILASTRO '+': AGGIUNTA ARTICOLI
  # ----------------------------------------------------------------------------
  def self.aggiungi_articoli(gruppo_id:, user_id:, items_text:, topic_id: 0)
    puts "[DATA_MONITOR] 📝 Scrittura Articoli -> G:#{gruppo_id} | T:#{topic_id} | U:#{user_id}"

    nomi = items_text.split(",").map(&:strip).reject(&:empty?)
    return [] if nomi.empty?

    ids_creati = [] # <--- Cambiamo il contatore in un array di ID

    DB.transaction do
      nomi.each do |nome|
        # Controllo duplicati esistente
        esiste = DB.get_first_value("SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND comprato = ''", [gruppo_id, topic_id, nome.downcase])

        if esiste
          ids_creati << esiste # Se esiste già, prendiamo l'ID esistente per l'eventuale foto
          next
        end

        DB.execute("INSERT INTO items (gruppo_id, topic_id, creato_da, nome) VALUES (?, ?, ?, ?)",
                   [gruppo_id, topic_id, user_id, nome])
        ids_creati << DB.last_insert_row_id # Recupera l'ID appena fatto
      end
    end

    puts "[DATA_MONITOR] ✅ Successo: #{ids_creati.size} record pronti."
    ids_creati # <--- Restituiamo gli ID invece dei nomi
  rescue => e
    puts "❌ [DATA_ERROR] Errore in aggiungi_articoli: #{e.message}"
    raise e
  end

  def self.salva_foto_articolo(item_id, file_id, file_unique_id)
    DB.execute(
      "INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
      [item_id, file_id, file_unique_id]
    )
  end

  # 1. VISIONE UTILIZZO (Portafoglio di Gruppo)
  # Da usare quando sei "dentro" una lista della spesa di un gruppo
  def self.carte_disponibili_nel_gruppo(g_id)
    query = <<-SQL
    SELECT c.id, c.nome, c.user_id, u.first_name as proprietario
    FROM carte_fedelta c
    JOIN gruppo_carte_collegamenti l ON c.id = l.carta_id
    LEFT JOIN user_names u ON c.user_id = u.user_id
    WHERE l.gruppo_id = ?
    ORDER BY LOWER(c.nome) ASC
  SQL
    DB.execute(query, [g_id])
  end

  # 2. VISIONE GESTIONE (Le mie condivisioni)
  # Da usare nel menu "Impostazioni" o "Le mie carte"
  def self.mie_carte_e_condivisioni(u_id)
    query = <<-SQL
    SELECT c.id, c.nome, GROUP_CONCAT(g.nome, ', ') as gruppi_nomi
    FROM carte_fedelta c
    LEFT JOIN gruppo_carte_collegamenti l ON c.id = l.carta_id
    LEFT JOIN gruppi g ON l.gruppo_id = g.id
    WHERE c.user_id = ?
    GROUP BY c.id
    ORDER BY LOWER(c.nome) ASC
  SQL
    DB.execute(query, [u_id])
  end

  def self.genera_header_contesto(g_id, t_id)
    g_id = g_id.to_i
    t_id = t_id.to_i

    return "👤 <b>LISTA PERSONALE</b>" if g_id == 0

    # Usiamo la logica di JOIN che hai già per recuperare entrambi i nomi
    res = DB.get_first_row(
      "SELECT g.nome as g_nome, t.nome as t_nome 
     FROM gruppi g 
     LEFT JOIN topics t ON g.chat_id = t.chat_id AND t.topic_id = ? 
     WHERE g.id = ?", [t_id, g_id]
    )

    return "🎯 <b>Gruppo #{g_id}</b>" unless res

    nome_gruppo = res["g_nome"]
    # CONSISTENZA: Se t_id è 0, usiamo "Generale". Se è un topic senza nome, usiamo "Topic ID"
    nome_topic = res["t_nome"] || (t_id == 0 ? "Generale" : "Topic #{t_id}")
    orario = Time.now.strftime("%H:%M:%S")
    "#{orario} <b>#{nome_gruppo}</b>: <i>#{nome_topic}</i>"
  end

  # In db.rb, dentro class DataManager
  # In db.rb, dentro class DataManager
  def self.aggiorna_nome_gruppo(chat_id, nuovo_nome)
    puts "[DB_QUERY] 📝 Tentativo UPDATE gruppi: ChatID:#{chat_id} -> '#{nuovo_nome}'"

    # Verifichiamo prima se il gruppo esiste
    esiste = DB.get_first_value("SELECT COUNT(*) FROM gruppi WHERE chat_id = ?", [chat_id])
    if esiste == 0
      puts "[DB_QUERY] ⚠️ Errore: Nessun gruppo trovato con ChatID #{chat_id}. Impossibile aggiornare nome."
      return
    end

    DB.execute("UPDATE gruppi SET nome = ? WHERE chat_id = ?", [nuovo_nome, chat_id])
    puts "[DB_QUERY] ✅ Nome gruppo aggiornato correttamente nel DB."
  rescue => e
    puts "[DB_QUERY] ❌ CRASH UPDATE GRUPPO: #{e.message}"
  end

  def self.puo_visualizzare?(user_id, carta_id, chat_id)
    is_group = chat_id.to_i < 0

    if is_group
      # Nel gruppo: la carta DEVE essere collegata a quel gruppo specifico
      query = <<-SQL
      SELECT 1 FROM gruppo_carte_collegamenti l
      JOIN gruppi g ON l.gruppo_id = g.id
      WHERE g.chat_id = ? AND l.carta_id = ? LIMIT 1
    SQL
      return !!DB.get_first_value(query, [chat_id, carta_id])
    else
      # In privata: la carta deve essere MIA o condivisa in UN gruppo di cui faccio parte
      query = <<-SQL
      SELECT 1 WHERE EXISTS (
        SELECT 1 FROM carte_fedelta WHERE user_id = ? AND id = ?
        UNION
        SELECT 1 FROM gruppo_carte_collegamenti l
        JOIN memberships m ON l.gruppo_id = m.gruppo_id
        WHERE m.user_id = ? AND l.carta_id = ?
      )
    SQL
      return !!DB.get_first_value(query, [user_id, carta_id, user_id, carta_id])
    end
  end

  # In db.rb
  def self.prendi_tutte_le_carte_accessibili(user_id)
    puts "[DB_TRACE] 🔍 Generazione lista per U:#{user_id}"

    query = <<-SQL
    WITH carte_unite AS (
      -- 1. Le tue carte personali (Proprietario sei TU)
      SELECT c.id, c.nome, c.user_id, NULL as initials
      FROM carte_fedelta c
      WHERE c.user_id = ?
      
      UNION ALL
      
      -- 2. Carte condivise da ALTRI nei gruppi dove sei presente
      -- (Usa DISTINCT per evitare duplicati della stessa carta da gruppi diversi)
      SELECT DISTINCT c.id, c.nome, c.user_id, u.initials
      FROM carte_fedelta c
      JOIN gruppo_carte_collegamenti l ON c.id = l.carta_id
      JOIN memberships m ON l.gruppo_id = m.gruppo_id
      LEFT JOIN user_names u ON c.user_id = u.user_id
      WHERE m.user_id = ? 
        AND c.user_id != ? -- Non mostrare le tue come "condivise"
    )
    SELECT id, 
           user_id,
           CASE 
             WHEN initials IS NOT NULL THEN nome || ' (' || initials || ')'
             ELSE nome 
           END as nome_display
    FROM carte_unite
    GROUP BY id, nome_display -- Pulizia finale
    ORDER BY LOWER(nome_display) ASC
  SQL

    res = DB.execute(query, [user_id, user_id, user_id])
    puts "[DB_TRACE] ✅ #{res.size} carte trovate nell'indice accessibile."
    res
  end

  def self.set_topic_name(chat_id, topic_id, nome)
    t_id = topic_id.to_i
    nome_pulito = nome.to_s.strip
    return if nome_pulito.empty?

    puts "[TRACE_DB] 📥 Scrittura Topic... G_Chat:#{chat_id} T:#{t_id} Nome:#{nome_pulito}"

    # RIMOSSO: DB.execute("UPDATE gruppi SET nome = ...")
    # Non dobbiamo toccare la tabella gruppi qui, altrimenti perdiamo il nome originale.

    query = <<-SQL
    INSERT INTO topics (chat_id, topic_id, nome) 
    VALUES (?, ?, ?)
    ON CONFLICT(chat_id, topic_id) 
    DO UPDATE SET nome = excluded.nome
  SQL

    DB.execute(query, [chat_id, t_id, nome_pulito])
    puts "[TRACE_DB] ✅ Record Topic salvato."
  rescue => e
    puts "[TRACE_DB] ❌ ERRORE: #{e.message}"
  end

  def self.prendi_carte_gruppo(g_id)
    query = <<-SQL
    SELECT c.id, c.nome, c.user_id
    FROM cards c
    JOIN group_card_links gcl ON c.id = gcl.carta_id
    WHERE gcl.gruppo_id = ?
    ORDER BY LOWER(c.nome) ASC
  SQL
    DB.execute(query, [g_id])
  end

  #  def self.prendi_per_contesto(g_id, t_id)
  #    query = <<-SQL
  #    SELECT
  #      i.*,
  #      u1.initials AS autore_init,
  #      u2.initials AS buyer_init
  #    FROM items i
  #    LEFT JOIN user_names u1 ON i.creato_da = u1.user_id
  #    LEFT JOIN user_names u2 ON CAST(i.comprato AS INTEGER) = u2.user_id
  #    WHERE i.gruppo_id = ? AND i.topic_id = ?
  #    ORDER BY (i.comprato != ''), i.id DESC
  #  SQL
  #    DB.execute(query, [g_id, t_id])
  #  end

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

 def self.aggiorna_membership(u_id, telegram_chat_id)
  # 1. Recuperiamo l'ID primario del database per quel gruppo
  g_id_db = DB.get_first_value("SELECT id FROM gruppi WHERE chat_id = ?", [telegram_chat_id])
puts "g_id_db #{g_id_db} telegram_chat_id: #{telegram_chat_id}"
  # Se il gruppo non esiste ancora nel DB, non possiamo creare la membership
  return if g_id_db.nil?

  # 2. Ora inseriamo usando l'ID corretto (es. 48 invece di -100...)
  query = <<-SQL
    INSERT INTO memberships (user_id, gruppo_id, last_seen)
    VALUES (?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(user_id, gruppo_id) DO UPDATE SET
    last_seen = CURRENT_TIMESTAMP
  SQL

  begin
    DB.execute(query, [u_id, g_id_db])
  rescue SQLite3::Exception => e
    puts "❌ [DB ERROR] Errore aggiorna_membership: #{e.message}"
  end
end

def self.prendi_destinazioni_censite(user_id)
    destinazioni = [{ "chat_id" => 0, "topic_id" => 0, "nome" => "👤 Lista Personale", "g_nome" => "Privata" }]

    sql = <<-SQL
      SELECT g.id, g.chat_id, t.topic_id, t.nome as t_nome, g.nome as g_nome
      FROM memberships m
      JOIN gruppi g ON m.gruppo_id = g.id
      LEFT JOIN topics t ON g.chat_id = t.chat_id  -- <--- CAMBIATO IN LEFT JOIN
      WHERE m.user_id = ?
    SQL

    res = DB.execute(sql, [user_id])
    res.each do |r|
      # Se t_nome è NULL (grazie al LEFT JOIN), topic_id sarà nullo o 0
      t_id = r["topic_id"] || 0
      t_label = r["t_nome"].to_s.strip.empty? ? (t_id == 0 ? "Generale" : "Topic #{t_id}") : r["t_nome"]

      destinazioni << {
        "chat_id" => r["id"],
        "topic_id" => t_id,
        "nome" => "👥 #{r["g_nome"]}: #{t_label}",
        "g_nome" => r["g_nome"],
      }
    end
    destinazioni
  end
    # In db.rb
  def self.prendi_ultimi_acquisti_con_nomi(gruppo_id, topic_id, limite = 15)
    sql = <<-SQL
    SELECT s.nome,
           s.updated_at,
           u1.initials AS autore_init,
           u2.initials AS buyer_init
    FROM storico_articoli s
    LEFT JOIN user_names u1 ON s.creato_da = u1.user_id
    LEFT JOIN user_names u2 ON s.comprato_da = u2.user_id
    WHERE s.gruppo_id = ? 
      AND s.topic_id = ? 
      AND s.conteggio > 0
    ORDER BY datetime(s.updated_at) DESC
    LIMIT ?
  SQL

    DB.execute(sql, [gruppo_id, topic_id, limite])
  end

  def self.prendi_articoli_ordinati(gruppo_id, topic_id)
    sql = <<-SQL
    SELECT i.*, 
           IFNULL(s.conteggio, 0) as volte, 
           u1.initials AS autore_init,
           u2.initials AS buyer_init,
           (SELECT COUNT(*) FROM item_images WHERE item_id = i.id) as ha_foto
    FROM items i
    LEFT JOIN storico_articoli s ON LOWER(i.nome) = LOWER(s.nome) 
      AND i.gruppo_id = s.gruppo_id AND i.topic_id = s.topic_id
    LEFT JOIN user_names u1 ON i.creato_da = u1.user_id 
    LEFT JOIN user_names u2 ON i.comprato = u2.user_id 
    WHERE i.gruppo_id = ? AND i.topic_id = ?
    ORDER BY 
      -- 1. I comprati vanno in fondo (0 se non comprato, 1 se comprato)
      (i.comprato IS NOT NULL AND i.comprato != '') ASC, 
      -- 2. Gli articoli più frequenti in alto
      volte DESC, 
      -- 3. I più recenti per primi tra quelli con stesse 'volte'
      i.id DESC
  SQL
    DB.execute(sql, [gruppo_id.to_i, topic_id.to_i])
  end

  def self.prendi_foto_articolo(item_id)
    # Restituisce un array di hash, es: [{"file_id" => "..."}]
    DB.execute("SELECT file_id FROM item_images WHERE item_id = ?", [item_id.to_i])
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
  # In db.rb, all'interno della classe DataManager

  def self.set_pending(chat_id:, topic_id:, action:, gruppo_id: 0)
    # Usiamo esattamente le colonne della tua tabella pending_actions
    puts "[DB_TRACE] 💾 Scrittura Pending -> Chat:#{chat_id} | Topic:#{topic_id} | Action:#{action}"

    sql = <<-SQL
    INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id, creato_il) 
    VALUES (?, ?, ?, ?, datetime('now'))
  SQL

    # Rimuoviamo initiator_id se non è presente nello schema fisico del tuo db.rb
    DB.execute(sql, [chat_id, topic_id, action, gruppo_id])
  end

  def self.ottieni_pending(chat_id, topic_id)
    puts "[DB_TRACE] 🔍 Ricerca Pending -> Chat:#{chat_id} | Topic:#{topic_id}"

    # Cerchiamo per la chiave primaria composta chat_id + topic_id
    sql = "SELECT * FROM pending_actions WHERE chat_id = ? AND topic_id = ? LIMIT 1"
    row = DB.get_first_row(sql, [chat_id, topic_id])

    if row
      puts "[DB_TRACE] ✅ Trovato: #{row["action"]}"
    else
      puts "[DB_TRACE] ❌ Nessun pending trovato"
    end
    row
  end

  def self.rimuovi_pending(chat_id, topic_id = 0)
    puts "[DB_TRACE] 🧹 Rimozione Pending -> Chat:#{chat_id} | Topic:#{topic_id}"

    # Cancellazione mirata per liberare la chiave primaria
    sql = "DELETE FROM pending_actions WHERE chat_id = ? AND topic_id = ?"
    DB.execute(sql, [chat_id, topic_id])
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

  # In db.rb all'interno di class DataManager
  # Aggiungi in class DataManager in db.rb
  def self.prendi_gruppo_da_chat_id(chat_id_telegram)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id_telegram])
  end

  # In db.rb all'interno di class DataManager

  # 1. Recupera i contesti (gruppi/topic) che contengono articoli rilevanti
  def self.prendi_gruppi_con_articoli(user_id, show_all_authors = false)
    if show_all_authors
      # Modalità "📦 TUTTI": Ogni gruppo/topic che ha ALMENO un articolo di CHIUNQUE
      query = <<-SQL
      SELECT DISTINCT g.id AS gruppo_id, g.nome AS gruppo_nome, g.chat_id, 
             COALESCE(i.topic_id, 0) AS topic_id, 0 AS ordine_lista
      FROM gruppi g
      JOIN memberships m ON g.id = m.gruppo_id
      JOIN items i ON g.id = i.gruppo_id
      UNION ALL
      SELECT 0, '👤 Lista Personale', NULL, 0, 1
      WHERE EXISTS (SELECT 1 FROM items WHERE gruppo_id = 0 AND creato_da = ?)
      ORDER BY ordine_lista DESC, gruppo_nome ASC, topic_id ASC
    SQL
      DB.execute(query, [user_id])
    else
      # Modalità "📋 I MIEI": Solo gruppi/topic dove IO ho aggiunto qualcosa
      query = <<-SQL
      SELECT DISTINCT COALESCE(g.id, 0) AS gruppo_id, 
             COALESCE(g.nome, '👤 Lista Personale') AS gruppo_nome,
             g.chat_id, COALESCE(i.topic_id, 0) AS topic_id
      FROM items i
      LEFT JOIN gruppi g ON i.gruppo_id = g.id
      WHERE i.creato_da = ?
      ORDER BY gruppo_id = 0 DESC, g.nome ASC, topic_id ASC
    SQL
      DB.execute(query, [user_id])
    end
  end

  # In db.rb, dentro la classe DataManager
  def self.get_real_chat_id(g_id)
    return nil if g_id == 0
    DB.get_first_value("SELECT chat_id FROM gruppi WHERE id = ?", [g_id])
  end

  # 2. Recupera gli articoli effettivi
  def self.prendi_articoli_per_storico(g_id, t_id, user_id, show_all)
    # Aggiungiamo la subquery identica a quella della lista standard
    base_query = <<-SQL
    SELECT i.*, u.initials AS autore_init,
           (SELECT COUNT(*) FROM item_images img WHERE img.item_id = i.id) as ha_foto_reale
    FROM items i
    LEFT JOIN user_names u ON i.creato_da = u.user_id
    WHERE i.gruppo_id = ? AND i.topic_id = ?
  SQL

    if show_all && g_id != 0
      DB.execute("#{base_query} ORDER BY (i.comprato != '' AND i.comprato IS NOT NULL), i.nome", [g_id, t_id])
    else
      DB.execute("#{base_query} AND i.creato_da = ? ORDER BY (i.comprato != '' AND i.comprato IS NOT NULL), i.nome", [g_id, t_id, user_id])
    end
  end

  def self.registra_gruppo_se_nuovo(chat_id, nome_gruppo, user_id)
    # 1. Cerchiamo se esiste già
    esistente = DB.get_first_row("SELECT id FROM gruppi WHERE chat_id = ?", [chat_id])
    return { status: :esistente, id: esistente["id"] } if esistente

    # 2. Se non esiste, inseriamo
    DB.execute(
      "INSERT INTO gruppi (nome, creato_da, chat_id) VALUES (?, ?, ?)",
      [nome_gruppo, user_id, chat_id]
    )
    nuovo_id = DB.get_first_value("SELECT last_insert_rowid()")
    { status: :creato, id: nuovo_id }
  rescue => e
    puts "❌ [DB ERROR] registra_gruppo: #{e.message}"
    { status: :errore, messaggio: e.message }
  end
end
