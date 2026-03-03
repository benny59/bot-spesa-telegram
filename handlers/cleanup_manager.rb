# handlers/cleanup_manager.rb
require "json" # Assicurati che sia caricato in alto nel file
require_relative "../models/whitelist"  # ci serve per verificare l'utente creatore
require_relative "../db"               # per poter invocare DataManager

class CleanupManager
  # ========================================
  # 🧹 CLEANUP COMPLETO
  # ========================================
  def self.esegui_cleanup(bot, chat_id, user_id)
    puts "\n" + "="*60
    puts "🚿 [CLEANUP] Avvio cleanup richiesto da user #{user_id}"
    puts "="*60

    # Solo il creatore può eseguire l'intero cleanup
    unless Whitelist.is_creator?(user_id)
      puts "🔒 [CLEANUP] utente #{user_id} non è creatore: operazione non autorizzata"
      begin
        bot.api.send_message(chat_id: chat_id, text: "❌ Solo il creatore può eseguire il cleanup.")
      rescue => e
        puts "❌ Impossibile inviare avviso chat: #{e.message}"
      end
      return
    end

    # Esegui backup del database prima del cleanup
    backup_file = DataManager.backup_database
    if backup_file
      bot.api.send_message(chat_id: chat_id, text: "💾 Backup del database effettuato: `#{File.basename(backup_file)}`", parse_mode: 'Markdown')
    else
      bot.api.send_message(chat_id: chat_id, text: "⚠️ Attenzione: Impossibile creare il backup del database.", parse_mode: 'Markdown')
    end

    # L'utente è creatore: eseguiamo anche la normalizzazione dello storico
    puts "🔄 [CLEANUP] utente #{user_id} è creatore: normalizzo storico articoli"
    begin
      puts "\n[CLEANUP] ▶️ Inizio DataManager.pulisci_storico_capitalize"
      DataManager.pulisci_storico_capitalize
      puts "[CLEANUP] ✅ DataManager.pulisci_storico_capitalize completata"
    rescue => normalize_err
      puts "[CLEANUP] ❌ ERRORE in pulisci_storico_capitalize: #{normalize_err.message}"
      puts normalize_err.backtrace[0..3].map { |line| "  #{line}" }.join("\n")
      
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore durante la normalizzazione dello storico:\n#{normalize_err.message}",
        parse_mode: "Markdown",
      )
      return
    end

    begin
      #puts "🚀 [DEBUG] Avvio sequenza cleanup per user: #{user_id}"
      #puts sonda_gruppi_semplici(bot)
      # 1. Scansione gruppi
      #esito_gruppi = self.pulisci_gruppi_inaccessibili(bot)
      #puts "📊 [DEBUG] Esito gruppi: #{esito_gruppi.inspect}"

      puts "\n[CLEANUP] ▶️ Inizio procedi_cleanup"
      puts procedi_cleanup(bot, user_id)
      puts "[CLEANUP] ✅ procedi_cleanup completato"

      # 2. Esecuzione pulizie orfani
      puts "\n[CLEANUP] ▶️ pulizia pending actions orfane..."
      p_actions = self.pulisci_pending_actions_orfane()
      puts "[CLEANUP] ✅ Pending actions rimosse: #{p_actions}"

      puts "\n[CLEANUP] ▶️ pulizia storico vecchio..."
      s_articoli = self.pulisci_storico_vecchio()
      puts "[CLEANUP] ✅ Storico rimosso: #{s_articoli}"

      puts "\n[CLEANUP] ▶️ pulizia items orfani..."
      i_orfani = self.pulisci_items_orfani()
      puts "[CLEANUP] ✅ Items orfani rimossi: #{i_orfani}"

      # Costruiamo l'hash risultati assicurandoci che nulla sia nil
      risultati = {
        #gruppi_rimossi: esito_gruppi[:rimossi] || [],
        #gruppi_migrati: esito_gruppi[:migrati] || [],
        pending_actions: p_actions || 0,
        storico_articoli: s_articoli || 0,
        items_orfani: i_orfani || 0,
      }

      puts "\n[CLEANUP] 📝 Risultati finali: #{risultati.inspect}"

      messaggio_riepilogo = genera_riepilogo_cleanup(risultati)

      bot.api.send_message(
        chat_id: chat_id,
        text: messaggio_riepilogo,
        parse_mode: "Markdown",
      )
      
      puts "\n" + "="*60
      puts "✅ [CLEANUP] Cleanup COMPLETATO con successo!"
      puts "="*60 + "\n"
      
    rescue => e
      puts "\n" + "="*60
      puts "❌ [ERROR] Errore critico nel metodo esegui_cleanup: #{e.message}"
      puts "="*60
      puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
      
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore durante il cleanup:\n#{e.message}",
        parse_mode: "Markdown",
      ) rescue nil
    end
  end

  def self.procedi_cleanup(bot, user_id)
    gruppi_rilevati = []

    # 1. Recuperiamo tutti i gruppi censiti nel DB
    tutti_i_gruppi = DB.execute("SELECT id, nome, chat_id FROM gruppi")

    tutti_i_gruppi.each do |gruppo|
      begin
        # 2. VERIFICA DOPPIA: Il bot è dentro? L'utente è dentro?
        # Telegram restituisce l'oggetto ChatMember se l'utente è presente
        membro = bot.api.get_chat_member(chat_id: gruppo["chat_id"], user_id: user_id)

        # Stati che indicano presenza attiva: creator, administrator, member, restricted
        presenza_attiva = ["creator", "administrator", "member", "restricted"].include?(membro.status)

        if presenza_attiva
          gruppi_rilevati << gruppo["nome"]

          # 3. AZIONE: Se l'utente è presente ma non era il creatore originale,
          # possiamo "marcare" l'appartenenza nel DB (es. aggiornando una tabella pivot o whitelist)
          # Per ora stampiamo un log di conferma
          puts "✅ Utente #{user_id} rilevato nel gruppo: #{gruppo["nome"]} (ID: #{gruppo["id"]})"
        end
      rescue Telegram::Bot::Exceptions::ResponseError => e
        # Se l'errore è 'user not found' o 'bot was kicked', saltiamo silenziosamente
        puts "❌ Impossibile verificare gruppo #{gruppo["nome"]}: #{e.message}"
      end
    end

    return gruppi_rilevati
  end

  def self.pulisci_gruppi_inaccessibili(bot)
    puts "🔍 [DEBUG] Inizio scansione e sonda gruppi..."
    gruppi = DB.execute("SELECT id, chat_id, nome FROM gruppi")
    rimossi = []
    migrati = []
    svegliati = []

    gruppi.each do |g|
      chat_id_str = g["chat_id"].to_s
      begin
        chat_info = bot.api.get_chat(chat_id: g["chat_id"])

        if chat_info.title && chat_info.title != g["nome"]
          DB.execute("UPDATE gruppi SET nome = ? WHERE id = ?", [chat_info.title, g["id"]])
          puts "📝 [UPDATE] Nome sincronizzato: #{g["nome"]} -> #{chat_info.title}"
          g["nome"] = chat_info.title
        end

        if !chat_id_str.start_with?("-100")
          bot.api.send_message(chat_id: g["chat_id"], text: "📡 *Sonda Visibilità* attiva.")
          svegliati << g["nome"]
          puts "📡 [PING] Gruppo semplice svegliato: #{g["nome"]}"
        end
      rescue Telegram::Bot::Exceptions::ResponseError => e
        body = e.response.body.is_a?(String) ? JSON.parse(e.response.body) : e.response.body
        nuovo_id = body.dig("parameters", "migrate_to_chat_id")

        if nuovo_id
          # --- LOGICA MERGE CORRETTA ---
          esistente = DB.get_first_row("SELECT id FROM gruppi WHERE chat_id = ?", [nuovo_id])

          if esistente
            puts "🔗 [MERGE] Trovato doppione con ID: #{esistente["id"]}. Fondendo record #{g["id"]} -> #{esistente["id"]}..."

            # Se la tua tabella items usa 'gruppo_id', spostiamo gli articoli sul record esistente
            # Usiamo un BEGIN/RESCUE interno per evitare crash se la colonna ha un nome diverso
            begin
              DB.execute("UPDATE items SET gruppo_id = ? WHERE gruppo_id = ?", [esistente["id"], g["id"]])
            rescue => e_sql
              puts "⚠️ [INFO] Salto update items: #{e_sql.message} (probabile struttura diversa)"
            end

            DB.execute("DELETE FROM gruppi WHERE id = ?", [g["id"]])
            migrati << "#{g["nome"]} (Unificato)"
          else
            puts "🔄 [DEBUG] Gruppo '#{g["nome"]}' migrato a #{nuovo_id}"
            DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [nuovo_id, g["id"]])
            migrati << "#{g["nome"]} (=> #{nuovo_id})"
          end
        else
          puts "🗑️ [DEBUG] Gruppo '#{g["nome"]}' inaccessibile. Rimuovo."
          rimossi << g["nome"]
          DB.execute("DELETE FROM gruppi WHERE id = ?", [g["id"]])
        end
      rescue => e
        puts "⚠️ [DEBUG] Errore imprevisto su #{g["nome"]}: #{e.message}"
      end
    end
    { rimossi: rimossi, migrati: migrati, svegliati: svegliati }
  end

  def self.sonda_gruppi_semplici(bot)
    gruppi = DB.execute("SELECT chat_id, nome FROM gruppi")
    pingati = 0

    gruppi.each do |g|
      chat_id = g["chat_id"].to_i

      # Verifichiamo se è un gruppo "semplice" (ID non inizia con -100)
      # Nota: su Telegram i supergruppi iniziano sempre con -100
      if chat_id < 0 && !g["chat_id"].to_s.start_with?("-100")
        begin
          # Inviamo un messaggio per rendere visibile la chat nel tuo client
          bot.api.send_message(
            chat_id: g["chat_id"],
            text: "🔍 *Sonda di visibilità*: questo gruppo è ancora attivo nel database del bot.",
          )
          puts "📡 Ping inviato a: #{g["nome"]} (#{g["chat_id"]})"
          pingati += 1
        rescue => e
          puts "❌ Impossibile pingare #{g["nome"]}: #{e.message}"
        end
      end
    end
    pingati
  end

  # ========================================
  # 🗑️ PULIZIA PENDING ACTIONS ORFANE (> 24 ore)
  # ========================================
  def self.pulisci_pending_actions_orfane
    begin
      records = DB.execute("SELECT chat_id, topic_id, action, creato_il FROM pending_actions WHERE creato_il < datetime('now', '-1 day')")
      if records.any?
        puts "🗑️ Rimuovo pending actions (#{records.size}):"
        records.each { |r| puts "   - chat=#{r['chat_id']} topic=#{r['topic_id']} action=#{r['action']} creato=#{r['creato_il']}" }
      else
        puts "ℹ️ Nessuna pending action vecchia da rimuovere"
      end

      count_prima = records.size
      DB.execute("DELETE FROM pending_actions WHERE creato_il < datetime('now', '-1 day')")
      rimossi = count_prima
      puts "✅ Pulite #{rimossi} pending actions vecchie"
      rimossi
    rescue => e
      puts "❌ Errore pulizia pending_actions: #{e.message}"
      0
    end
  end

  # ========================================
  # 📊 PULIZIA STORICO ARTICOLI VECCHI
  # (1 acquisto > 1 anno fa)
  # ========================================
  def self.pulisci_storico_vecchio
    begin
      # selezioniamo sia gli articoli con singolo acquisto >1 anno sia
    # quelli con al massimo 2 acquisti aggiornati da più di 2 anni
    rows = DB.execute(
      "SELECT id, gruppo_id, topic_id, nome, conteggio, ultima_aggiunta, updated_at \
       FROM storico_articoli \
       WHERE (conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')) \
          OR (conteggio <= 2 AND updated_at < datetime('now', '-2 years'))"
    )
    if rows.any?
      puts "🗃️ Rimuovo dal storico (#{rows.size} voci vecchie/sotto-conteggio):"
      rows.each do |r|
        puts "   - id=#{r['id']} nome=#{r['nome']} cnt=#{r['conteggio']} ultime=#{r['ultima_aggiunta']} upd=#{r['updated_at']}"
      end
    else
      puts "ℹ️ Nessun articolo storico vecchio o con conteggio basso da rimuovere"
    end

    count_prima = rows.size
    DB.execute(
      "DELETE FROM storico_articoli \
       WHERE (conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')) \
          OR (conteggio <= 2 AND updated_at < datetime('now', '-2 years'))"
    )
    rimossi = count_prima
    puts "✅ Puliti #{rimossi} articoli storico vecchi"
    rimossi
    rescue => e
      puts "❌ Errore pulizia storico_articoli: #{e.message}"
      0
    end
  end

  # ========================================
  # 🗂️ PULIZIA ITEMS ORFANI (gruppo cancellato)
  # ========================================
  def self.pulisci_items_orfani
    begin
      rows = DB.execute("SELECT id, nome, gruppo_id, topic_id FROM items WHERE gruppo_id != 0 AND gruppo_id NOT IN (SELECT id FROM gruppi)")
      if rows.any?
        puts "🗂️ Cancello items orfani (#{rows.size}):"
        rows.each { |r| puts "   - id=#{r['id']} nome=#{r['nome']} gruppo=#{r['gruppo_id']} topic=#{r['topic_id']}" }
      else
        puts "ℹ️ Nessun item orfano trovato"
      end

      count_prima = rows.size
      DB.execute("DELETE FROM items WHERE gruppo_id != 0 AND gruppo_id NOT IN (SELECT id FROM gruppi)")
      rimossi = count_prima
      puts "✅ Puliti #{rimossi} items orfani"
      rimossi
    rescue => e
      puts "❌ Errore pulizia items orfani: #{e.message}"
      0
    end
  end

  # ========================================
  # 📋 GENERA RIEPILOGO
  # ========================================
  def self.genera_riepilogo_cleanup(risultati)
    rimossi = risultati[:gruppi_rimossi] || []
    migrati = risultati[:gruppi_migrati] || []
    # Ottieni le statistiche PRIMA del cleanup
    begin
      stats_pre = {
        pending_actions_vecchie: DB.get_first_value("SELECT COUNT(*) FROM pending_actions WHERE creato_il < datetime('now', '-1 day')") || 0,
        storico_vecchio: DB.get_first_value("SELECT COUNT(*) FROM storico_articoli WHERE conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')") || 0,
        items_orfani: DB.get_first_value("SELECT COUNT(*) FROM items WHERE gruppo_id NOT IN (SELECT id FROM gruppi)") || 0,
      }
    rescue => e
      puts "❌ Errore statistiche pre-cleanup: #{e.message}"
      stats_pre = { pending_actions_vecchie: 0, storico_vecchio: 0, items_orfani: 0 }
    end

    # Sezione Gruppi Rimossi
    sez_gruppi = ""
    if rimossi.any?
      sez_gruppi += "🗑️ *Gruppi rimossi (inaccessibili):*\n"
      rimossi.each { |nome| sez_gruppi += "• #{nome}\n" }
    end

    # Sezione Segnalazioni Migrazione
    sez_migrati = ""
    if migrati.any?
      sez_migrati += "\n🔍 *ATTENZIONE - Migrazioni rilevate:*\n"
      migrati.each { |info| sez_migrati += "• #{info}\n" }
      sez_migrati += "_L'ID nel DB va aggiornato manualmente._\n"
    end

    # Calcolo totale per il messaggio finale
    total_azioni = risultati[:pending_actions].to_i +
                   risultati[:storico_articoli].to_i +
                   risultati[:items_orfani].to_i +
                   rimossi.size

    <<~TEXT
      🧹 *CLEANUP COMPLETATO*

      #{sez_gruppi}#{sez_migrati}
      📊 *Risultati della pulizia:*
      • 🗑️ Pending actions: #{stats_pre[:pending_actions_vecchie]} → #{risultati[:pending_actions]}
      • 📊 Articoli storico: #{stats_pre[:storico_vecchio]} → #{risultati[:storico_articoli]}
      • 🗂️ Items orfani: #{stats_pre[:items_orfani]} → #{risultati[:items_orfani]}

      ✅ #{total_azioni > 0 ? "Database pulito!" : "Database già ottimizzato!"}
    TEXT
  end

  # ========================================
  # 🔍 STATISTICHE DATABASE (opzionale)
  # ========================================
  def self.statistiche_database
    begin
      stats = {
        pending_actions: DB.get_first_value("SELECT COUNT(*) FROM pending_actions"),
        pending_actions_vecchie: DB.get_first_value("SELECT COUNT(*) FROM pending_actions WHERE creato_il < datetime('now', '-1 day')"),
        storico_articoli: DB.get_first_value("SELECT COUNT(*) FROM storico_articoli"),
        storico_vecchio: DB.get_first_value("SELECT COUNT(*) FROM storico_articoli WHERE conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')"),
        items_orfani: DB.get_first_value("SELECT COUNT(*) FROM items WHERE gruppo_id NOT IN (SELECT id FROM gruppi)"),
      }
      stats
    rescue => e
      puts "❌ Errore statistiche database: #{e.message}"
      {}
    end
  end
end
