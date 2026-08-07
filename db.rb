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
  db.execute <<-SQL
    CREATE TABLE IF NOT EXISTS link_pins (
      pin TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL,
      first_name TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  SQL

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
  def self.backup_database
    require 'fileutils'
    backup_dir = "data/backups"
    FileUtils.mkdir_p(backup_dir)
    
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    backup_file = File.join(backup_dir, "spesa_#{timestamp}.db")
    
    if File.exist?(DB_PATH)
      FileUtils.cp(DB_PATH, backup_file)
      puts "✅ [DB] Backup creato con successo: #{backup_file}"
      return backup_file
    else
      puts "❌ [DB] File database non trovato, impossibile creare il backup"
      return nil
    end
  end

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

  # Helper DRY per UPSERT storico_articoli (consolidato da esegui_scopetta e storico_manager)
  # Parametri creato_da_id e comprato_da_id sono opzionali (usati da esegui_scopetta, nil da storico_manager)
  def self.upsert_storico_articolo(gruppo_id, topic_id, nome, creato_da_id = nil, comprato_da_id = nil)
    # Normalizza il nome: case-insensitive (Insalata = insalata)
    nome_normalizzato = nome.to_s.strip.downcase
    nome_formattato = nome_normalizzato.capitalize

    puts "  📝 [UPSERT] Elaborazione: '#{nome_formattato}' (G:#{gruppo_id}, T:#{topic_id})"

    # CONSOLIDAMENTO: Se esistono duplicati case-different (o in topic_id diversi), consolidarli PRIMA
    # ATTENZIONE: Il constraint unico è UNIQUE(nome, gruppo_id), quindi non filtriamo per topic_id qui!
    duplicati = DB.execute(
      "SELECT id, conteggio, topic_id FROM storico_articoli WHERE LOWER(nome) = ? AND gruppo_id = ? ORDER BY id ASC",
      [nome_normalizzato, gruppo_id]
    )

    puts "  📊 [UPSERT] Trovati #{duplicati.size} record pre-esistenti per il nome"

    if duplicati.size > 1
      # Manteniamo il primo (ID più basso), consolidando gli altri
      keep_id = duplicati[0]["id"]
      total_count = duplicati.reduce(0) { |sum, rec| sum + rec["conteggio"].to_i }
      to_delete_ids = duplicati[1..-1].map { |rec| rec["id"] }

      puts "  ⚠️ [CONSOLIDAMENTO PRE-UPSERT] Mantenimento ID=#{keep_id}, Eliminazione IDs=#{to_delete_ids.inspect}"

      # Recupera le date più recenti
      max_dates = DB.execute(
        "SELECT MAX(updated_at) AS max_upd, MAX(ultima_aggiunta) AS max_ult FROM storico_articoli WHERE id IN (#{duplicati.map { "?" }.join(",")})",
        duplicati.map { |rec| rec["id"] }
      )[0]

      # Aggiorna il record da mantenere al conteggio totale e nome Capitalize, e all'ultimo topic_id
      DB.execute(
        "UPDATE storico_articoli SET nome = ?, topic_id = ?, conteggio = ?, updated_at = ?, ultima_aggiunta = ? WHERE id = ?",
        [nome_formattato, topic_id, total_count, max_dates["max_upd"], max_dates["max_ult"], keep_id]
      )

      puts "  ✅ [UPSERT] Record #{keep_id} aggiornato con conteggio=#{total_count}"

      # Elimina i duplicati
      to_delete_ids.each do |del_id|
        DB.execute("DELETE FROM storico_articoli WHERE id = ?", [del_id])
        puts "  ✅ [UPSERT] Record #{del_id} eliminato"
      end
    end

    # ORA procedi con UPDATE o INSERT sul record (che ora è unico per nome+gruppo_id)
    esistente = DB.get_first_row(
      "SELECT id FROM storico_articoli WHERE LOWER(nome) = ? AND gruppo_id = ?",
      [nome_normalizzato, gruppo_id]
    )

    if esistente
      # Aggiorna il record consolidato
      puts "  🔄 [UPSERT] UPDATE - Record esiste (ID=#{esistente["id"]})"
      if creato_da_id && comprato_da_id
        DB.execute(
          "UPDATE storico_articoli SET nome = ?, topic_id = ?, conteggio = conteggio + 1, creato_da = ?, comprato_da = ?, updated_at = datetime('now') WHERE id = ?",
          [nome_formattato, topic_id, creato_da_id, comprato_da_id, esistente["id"]]
        )
      else
        DB.execute(
          "UPDATE storico_articoli SET nome = ?, topic_id = ?, conteggio = conteggio + 1, ultima_aggiunta = datetime('now'), updated_at = datetime('now') WHERE id = ?",
          [nome_formattato, topic_id, esistente["id"]]
        )
      end
      puts "  ✅ [UPSERT] UPDATE completato"
    else
      # Inserisce il nuovo record in formato Capitalize
      puts "  ➕ [UPSERT] INSERT - Nuovo record"
      if creato_da_id && comprato_da_id
        DB.execute(
          "INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, creato_da, comprato_da, ultima_aggiunta) VALUES (?, ?, ?, 1, ?, ?, datetime('now'))",
          [gruppo_id, topic_id, nome_formattato, creato_da_id, comprato_da_id]
        )
      else
        DB.execute(
          "INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, ultima_aggiunta, updated_at) VALUES (?, ?, ?, 1, datetime('now'), datetime('now'))",
          [gruppo_id, topic_id, nome_formattato]
        )
      end
      puts "  ✅ [UPSERT] INSERT completato"
    end
  end

  # LA SCOPETTA (Cleanup & Storico)
  # ----------------------------------------------------------------------------
  # Cancella gli articoli comprati e aggiorna il conteggio nello storico
  def self.esegui_scopetta(gruppo_id, topic_id = 0, target_ids = nil)
    puts "\n🧹 [SCOPETTA] Inizio esegui_scopetta - G:#{gruppo_id}, T:#{topic_id}"
    
    if target_ids && !target_ids.empty?
      placeholders = target_ids.map { "?" }.join(",")
      query = "SELECT id, nome, creato_da, comprato FROM items WHERE id IN (#{placeholders})"
      params = target_ids
      puts "🧹 [SCOPETTA] Modalità: target_ids (#{target_ids.size} items)"
    else
      query = "SELECT id, nome, creato_da, comprato FROM items WHERE gruppo_id = ? AND topic_id = ? AND comprato != ''"
      params = [gruppo_id, topic_id]
      puts "🧹 [SCOPETTA] Modalità: query da DB"
    end

    comprati = DB.execute(query, params)
    puts "🧹 [SCOPETTA] Articoli comprati trovati: #{comprati.size}"
    return 0 if comprati.empty?

    DB.transaction do
      comprati.each do |item|
        puts "🧹 [SCOPETTA] Elaborando: '#{item["nome"]}' (ID:#{item["id"]})"
        # Usa il metodo DRY unificato per UPSERT storico
        self.upsert_storico_articolo(gruppo_id, topic_id, item["nome"], item["creato_da"], item["comprato"])
      end

      puts "🧹 [SCOPETTA] Cancellazione items..."
      ids_del = comprati.map { |i| i["id"] }
      p_del = ids_del.map { "?" }.join(",")
      DB.execute("DELETE FROM item_images WHERE item_id IN (#{p_del})", ids_del)
      puts "🧹 [SCOPETTA] Images cancellate: #{ids_del.size}"
      
      DB.execute("DELETE FROM items WHERE id IN (#{p_del})", ids_del)
      puts "🧹 [SCOPETTA] Items cancellati: #{ids_del.size}"
    end
    
    puts "✅ [SCOPETTA] Completata - #{comprati.size} articoli elaborati\n"
    comprati.size
  end

  # ----------------------------------------------------------------------------
  # REGISTRAZIONE UTENTE (WHITELIST)
  # ----------------------------------------------------------------------------
def self.registra_utente(user_id, first_name, last_name)
    fn = first_name.to_s.upcase.gsub(/[^A-Z]/, '')
    ln = last_name.to_s.upcase.gsub(/[^A-Z]/, '')
    
    # 1. Costruiamo il vettore di tutte le combinazioni possibili (senza duplicati)
    possibilita = []
    
    # A. Nome fisso (prima lettera) + scorrimento lettere cognome (es: MB, ME, MN...)
    if fn[0]
      ln.chars.each { |char_l| possibilita << "#{fn[0]}#{char_l}" }
    end
    
    # B. Cognome fisso (prima lettera) + scorrimento lettere nome (es: MB, AB, RB...)
    if ln[0]
      fn.chars.each { |char_f| possibilita << "#{char_f}#{ln[0]}" }
    end
    
    # C. Tutte le combinazioni incrociate rimanenti (es: MA, MT, EB, EN...)
    fn.chars.each do |char_f|
      ln.chars.each { |char_l| possibilita << "#{char_f}#{char_l}" }
    end

    # Pulizia: togliamo duplicati e stringhe corte
    possibilita = possibilita.uniq.select { |p| p.length == 2 }
    
    # 2. Cerchiamo la prima libera nel database
    initials = nil
    possibilita.each do |p|
      # Verifichiamo se p è già usato da un ALTRO utente
      count = DB.get_first_value("SELECT COUNT(*) FROM user_names WHERE initials = ? AND user_id != ?", [p, user_id]).to_i
      if count == 0
        initials = p
        break
      end
    end

    # 3. Fallback estremo
    initials ||= "UT"

    # 4. Salvataggio atomico (wrappato in transazione per consistenza)
    DB.transaction do
      DB.execute(
        "INSERT OR REPLACE INTO user_names (user_id, first_name, last_name, initials, aggiornato_il) 
         VALUES (?, ?, ?, ?, datetime('now'))",
        [user_id, first_name, last_name, initials]
      )
      
      DB.execute("INSERT OR IGNORE INTO whitelist (user_id, added_at) VALUES (?, datetime('now'))", [user_id])
    end
    
    puts "🎨 [INITIALS] Per #{first_name} #{last_name} assegnato: [#{initials}]"
  rescue => e
    puts "❌ [DATA_ERROR] Errore registrazione utente: #{e.message}"
  end
  
  # In db.rb -> class DataManager

# Verifica se l'articolo è già "attivo" in lista
def self.in_lista?(g_id, t_id, nome)
  DB.get_first_value(
    "SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND (comprato IS NULL OR comprato = '')",
    [g_id, t_id, nome.downcase]
  )
end

# Rimuove l'articolo attivo (per la deselezione dalla checklist)
def self.rimuovi_da_lista(item_id)
  DB.execute("DELETE FROM items WHERE id = ?", [item_id])
end

# Ripristino DRY unificato per inserimento da storico (usato dalla checklist)
# Usa INSERT OR IGNORE per evitare doppioni se l'utente clicca due volte velocemente
def self.ripristina_da_checklist(g_id, t_id, nome, user_id)
  DB.execute(
    "INSERT OR IGNORE INTO items (gruppo_id, topic_id, nome, creato_da) VALUES (?, ?, ?, ?)",
    [g_id, t_id, nome, user_id]
  )
end

# Alias per retrocompatibilità (rimanda a ripristina_da_checklist)
def self.ripristina_da_storico(g_id, t_id, nome, user_id)
  self.ripristina_da_checklist(g_id, t_id, nome, user_id)
end

# Verifichiamo che questo metodo esista (riga 259 del tuo file)
def self.prendi_telegram_chat_id(g_id)
  return nil if g_id == 0
  DB.get_first_value("SELECT chat_id FROM gruppi WHERE id = ?", [g_id])
end

	
  # ----------------------------------------------------------------------------
  # PILASTRO '+': AGGIUNTA ARTICOLI
  # ----------------------------------------------------------------------------
  def self.aggiungi_articoli(gruppo_id:, user_id:, items_text:, topic_id: 0)
    puts "[DATA_MONITOR] 📝 Scrittura Articoli -> G:#{gruppo_id} | T:#{topic_id} | U:#{user_id}"

    nomi = items_text.split(",").map(&:strip).reject(&:empty?)
    # non forziamo il minuscolo: lasciamo libera la formattazione dell'utente
    return [] if nomi.empty?

    ids_creati = [] # <--- Cambiamo il contatore in un array di ID

    DB.transaction do
      nomi.each do |nome|
        # Controllo duplicati esistente (case‑insensitive)
        esiste = DB.get_first_value("SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND comprato = ''", [gruppo_id, topic_id, nome.downcase])

        if esiste
          ids_creati << esiste # Se esiste già, prendiamo l'ID esistente per l'eventuale foto
          next
        end

        # Inseriamo esattamente come scritto dall'utente (libertà di formattazione)
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

  # ========================================
  # 🔧 NORMALIZZAZIONE STORICO ARTICOLI
  # Questa routine viene eseguita occasionalmente dal cleanup_manager,
  # e può essere richiamata soltanto dal creatore dell'app (whitelist).
  # L'obiettivo è:
  # 1. salvare i nuovi record con nomi capitalizzati (prima lettera maiuscola)
  # 2. unire righe duplicate create solo per differenze di case
  # L'operazione è idempotente e avvolta in transazione.
  # ========================================
  # 🔧 NORMALIZZAZIONE STORICO ARTICOLI
  # Questa routine viene eseguita occasionalmente dal cleanup_manager,
  # e può essere richiamata soltanto dal creatore dell'app (whitelist).
  # L'obiettivo è:
  # 1. salvare i nuovi record con nomi capitalizzati (prima lettera maiuscola)
  # 2. unire righe duplicate create solo per differenze di case
  # L'operazione è idempotente e avvolta in transazione.
  def self.pulisci_storico_capitalize
    puts "\n🔧 [CLEANUP] Inizio pulisci_storico_capitalize..."
    
    DB.transaction do
      # 1. Pulisci i record con nome vuoto/NULL
      empty_records = DB.execute("SELECT id FROM storico_articoli WHERE nome IS NULL OR nome = ''")
      if empty_records.size > 0
        ids_to_delete = empty_records.map { |r| r["id"] }
        placeholders = ids_to_delete.map { "?" }.join(",")
        DB.execute("DELETE FROM storico_articoli WHERE id IN (#{placeholders})", ids_to_delete)
        puts "   ✓ Eliminati #{ids_to_delete.size} record con nome vuoto"
      end
      
      # 2. Trova e consolida i duplicati che l'UPDATE creerebbe
      # L'indice del DB usa UNIQUE(nome, gruppo_id)
      duplicates_query = <<~SQL
        SELECT 
          UPPER(SUBSTR(LOWER(nome),1,1)) || SUBSTR(LOWER(nome),2) as nome_normalizzato,
          gruppo_id,
          MAX(topic_id) as topic_id_scelto,
          GROUP_CONCAT(id) as ids,
          SUM(conteggio) as total_count
        FROM storico_articoli
        GROUP BY UPPER(SUBSTR(LOWER(nome),1,1)) || SUBSTR(LOWER(nome),2), gruppo_id
        HAVING COUNT(*) > 1
      SQL
      
      duplicates = DB.execute(duplicates_query)
      if duplicates.size > 0
        duplicates.each do |dup|
          ids = dup["ids"].split(",").map(&:to_i)
          total = dup["total_count"]
          topic_scelto = dup["topic_id_scelto"] || 0
          
          # Elimina tutti i duplicati
          placeholders = ids.map { "?" }.join(",")
          DB.execute("DELETE FROM storico_articoli WHERE id IN (#{placeholders})", ids)
          
          # Inserisce uno consolidato
          DB.execute(
            "INSERT INTO storico_articoli (gruppo_id, topic_id, nome, conteggio, updated_at, ultima_aggiunta) VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))",
            [dup["gruppo_id"], topic_scelto, dup["nome_normalizzato"], total]
          )
        end
        puts "   ✓ Consolidati #{duplicates.size} insiemi di duplicati pre-esistenti"
      end
      
      # 3. Normalizza tutti i nomi
      count_before = DB.get_first_value("SELECT COUNT(*) FROM storico_articoli").to_i
      DB.execute("UPDATE storico_articoli SET nome = UPPER(SUBSTR(LOWER(nome),1,1)) || SUBSTR(LOWER(nome),2)")
      count_after = DB.get_first_value("SELECT COUNT(*) FROM storico_articoli").to_i
      
      puts "   ✓ Normalizzazione completata (#{count_before} → #{count_after} record)"
    end
    
    puts "✅ [CLEANUP] pulisci_storico_capitalize COMPLETATA CON SUCCESSO"
  rescue => e
    puts "❌ [DATA_ERROR] pulisci_storico_capitalize fallita: #{e.message}"
    raise
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
  # DRY: Metodo unificato per sincronizzazione nome gruppo (usato da aggiorna_nome_gruppo e cleanup_manager)
  def self.sincronizza_nome_gruppo(chat_id, nuovo_nome)
    nuovo_nome_pulito = nuovo_nome.to_s.strip
    return if nuovo_nome_pulito.empty?

    # Verifichiamo prima se il gruppo esiste
    esiste = DB.get_first_value("SELECT COUNT(*) FROM gruppi WHERE chat_id = ?", [chat_id])
    if esiste == 0
      puts "[DB_QUERY] ⚠️ Errore: Nessun gruppo trovato con ChatID #{chat_id}. Impossibile aggiornare nome."
      return
    end

    DB.execute("UPDATE gruppi SET nome = ? WHERE chat_id = ?", [nuovo_nome_pulito, chat_id])
    puts "[DB_QUERY] ✅ Nome gruppo aggiornato: '#{nuovo_nome_pulito}'"
  rescue => e
    puts "[DB_QUERY] ❌ Errore UPDATE GRUPPO: #{e.message}"
  end

  # Alias per retrocompatibilità
  def self.aggiorna_nome_gruppo(chat_id, nuovo_nome)
    self.sincronizza_nome_gruppo(chat_id, nuovo_nome)
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

  def self.get_nome_articolo(item_id)
    nome = DB.get_first_value("SELECT nome FROM items WHERE id = ?", [item_id.to_i])
    puts "🔍 [DB_TRACE] ID:#{item_id} -> Nome recuperato: '#{nome}'"
    nome
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

  # Helper DRY: Base query articoli con JOIN a user_names (riutilizzato in più metodi)
  def self.get_base_query_articoli_con_metadata
    <<-SQL
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
    SQL
  end

  def self.prendi_articoli_ordinati(gruppo_id, topic_id)
    sql = self.get_base_query_articoli_con_metadata + <<-SQL
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
      sql += " AND LOWER(nome) LIKE ?"
      params << "%#{query.downcase}%"
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

  # Helper DRY: Carica config con default integrati
  def self.get_config_completa_utente(user_id, fallback_g_id = 0, fallback_t_id = 0)
    config = self.carica_config_utente(user_id)
    return {
      "db_id" => fallback_g_id,
      "topic_id" => fallback_t_id
    } if config.nil? || config.empty?
    config
  end

  def self.salva_config_utente(user_id, config_hash)
    puts "[DATA_MONITOR] ⚙️ Update Context Utente: #{user_id}"
    DB.execute(
      "INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)",
      ["context:#{user_id}", config_hash.to_json]
    )
  end
  # ==============================================================================
  # SUPERSCOPETTA: Pulizia trasversale (Miei o Tutti)
  # ==============================================================================
  # In db.rb (DataManager)
  def self.articoli_da_superscopetta(user_id, show_all)
    if show_all
      # Query corretta basata sul tuo db.rb
      sql = <<-SQL
        SELECT i.id, i.nome, i.gruppo_id, i.topic_id
        FROM items i
        WHERE i.comprato != '' AND i.comprato IS NOT NULL
        AND (
          (i.gruppo_id = 0 AND i.creato_da = ?) 
          OR 
          i.gruppo_id IN (SELECT gruppo_id FROM memberships WHERE user_id = ?)
        )
      SQL
      params = [user_id, user_id]
    else
      sql = "SELECT id, nome, gruppo_id, topic_id FROM items WHERE (comprato != '' AND comprato IS NOT NULL) AND creato_da = ?"
      params = [user_id]
    end
    DB.execute(sql, params)
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

    # Cancellazione mirata per liberare la chiave primaria (unico metodo di delete)
    sql = "DELETE FROM pending_actions WHERE chat_id = ? AND topic_id = ?"
    DB.execute(sql, [chat_id, topic_id])
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
  # Recupera gruppo da chat_id Telegram. Torna hash vuoto se non trovato (fallback sicuro)
  def self.prendi_gruppo_da_chat_id(chat_id_telegram)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id_telegram]) || {}
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
