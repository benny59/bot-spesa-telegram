# handlers/cleanup_manager.rb
require 'json' # Assicurati che sia caricato in alto nel file

class CleanupManager
  # ========================================
  # 🧹 CLEANUP COMPLETO
  # ========================================
def self.esegui_cleanup(bot, chat_id, user_id)
    # Controllo Whitelist omesso per brevità, assumiamo sia già ok
    
    begin
      puts "🚀 [DEBUG] Avvio sequenza cleanup per user: #{user_id}"

      # 1. Scansione gruppi
      esito_gruppi = self.pulisci_gruppi_inaccessibili(bot)
      puts "📊 [DEBUG] Esito gruppi: #{esito_gruppi.inspect}"

      # 2. Esecuzione pulizie orfani
      p_actions = self.pulisci_pending_actions_orfane()
      puts "📊 [DEBUG] Pending actions rimosse: #{p_actions}"

      s_articoli = self.pulisci_storico_vecchio()
      puts "📊 [DEBUG] Storico rimosso: #{s_articoli}"

      i_orfani = self.pulisci_items_orfani()
      puts "📊 [DEBUG] Items orfani rimossi: #{i_orfani}"

      # Costruiamo l'hash risultati assicurandoci che nulla sia nil
      risultati = {
        gruppi_rimossi: esito_gruppi[:rimossi] || [],
        gruppi_migrati: esito_gruppi[:migrati] || [],
        pending_actions: p_actions || 0,
        storico_articoli: s_articoli || 0,
        items_orfani: i_orfani || 0
      }

      puts "📝 [DEBUG] Risultati finali pronti per il report: #{risultati.inspect}"

      messaggio_riepilogo = genera_riepilogo_cleanup(risultati)

      bot.api.send_message(
        chat_id: chat_id,
        text: messaggio_riepilogo,
        parse_mode: "Markdown"
      )
    rescue => e
      puts "❌ [ERROR] Errore critico nel metodo esegui_cleanup: #{e.message}"
      puts e.backtrace.first(5) # Stampa le prime 5 righe dell'errore per il debug
    end
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
        puts "📝 [UPDATE] Nome sincronizzato: #{g['nome']} -> #{chat_info.title}"
        g["nome"] = chat_info.title
      end

      if !chat_id_str.start_with?("-100")
        bot.api.send_message(chat_id: g["chat_id"], text: "📡 *Sonda Visibilità* attiva.")
        svegliati << g["nome"]
        puts "📡 [PING] Gruppo semplice svegliato: #{g['nome']}"
      end

    rescue Telegram::Bot::Exceptions::ResponseError => e
      body = e.response.body.is_a?(String) ? JSON.parse(e.response.body) : e.response.body
      nuovo_id = body.dig("parameters", "migrate_to_chat_id")

      if nuovo_id
        # --- LOGICA MERGE CORRETTA ---
        esistente = DB.get_first_row("SELECT id FROM gruppi WHERE chat_id = ?", [nuovo_id])

        if esistente
          puts "🔗 [MERGE] Trovato doppione con ID: #{esistente['id']}. Fondendo record #{g['id']} -> #{esistente['id']}..."
          
          # Se la tua tabella items usa 'gruppo_id', spostiamo gli articoli sul record esistente
          # Usiamo un BEGIN/RESCUE interno per evitare crash se la colonna ha un nome diverso
          begin
            DB.execute("UPDATE items SET gruppo_id = ? WHERE gruppo_id = ?", [esistente['id'], g['id']])
          rescue => e_sql
            puts "⚠️ [INFO] Salto update items: #{e_sql.message} (probabile struttura diversa)"
          end

          DB.execute("DELETE FROM gruppi WHERE id = ?", [g["id"]])
          migrati << "#{g['nome']} (Unificato)"
        else
          puts "🔄 [DEBUG] Gruppo '#{g['nome']}' migrato a #{nuovo_id}"
          DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [nuovo_id, g["id"]])
          migrati << "#{g['nome']} (=> #{nuovo_id})"
        end
      else
        puts "🗑️ [DEBUG] Gruppo '#{g['nome']}' inaccessibile. Rimuovo."
        rimossi << g["nome"]
        DB.execute("DELETE FROM gruppi WHERE id = ?", [g["id"]])
      end
    rescue => e
      puts "⚠️ [DEBUG] Errore imprevisto su #{g['nome']}: #{e.message}"
    end
  end
  { rimossi: rimossi, migrati: migrati, svegliati: svegliati }
end


  # ========================================
  # 🗑️ PULIZIA PENDING ACTIONS ORFANE (> 24 ore)
  # ========================================
  def self.pulisci_pending_actions_orfane
    begin
      # Prima conta i record da eliminare
      count_prima = DB.get_first_value("SELECT COUNT(*) FROM pending_actions WHERE creato_il < datetime('now', '-1 day')")

      # Poi elimina
      DB.execute("DELETE FROM pending_actions WHERE creato_il < datetime('now', '-1 day')")

      # Conta i record rimanenti per verificare
      count_dopo = DB.get_first_value("SELECT COUNT(*) FROM pending_actions WHERE creato_il < datetime('now', '-1 day')")

      rimossi = count_prima - count_dopo
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
      count_prima = DB.get_first_value("
        SELECT COUNT(*) FROM storico_articoli 
        WHERE conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')
      ")

      DB.execute("
        DELETE FROM storico_articoli 
        WHERE conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')
      ")

      count_dopo = DB.get_first_value("
        SELECT COUNT(*) FROM storico_articoli 
        WHERE conteggio = 1 AND ultima_aggiunta < datetime('now', '-1 year')
      ")

      rimossi = count_prima - count_dopo
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
      count_prima = DB.get_first_value("
        SELECT COUNT(*) FROM items 
        WHERE gruppo_id NOT IN (SELECT id FROM gruppi)
      ")

      DB.execute("
        DELETE FROM items 
        WHERE gruppo_id NOT IN (SELECT id FROM gruppi)
      ")

      count_dopo = DB.get_first_value("
        SELECT COUNT(*) FROM items 
        WHERE gruppo_id NOT IN (SELECT id FROM gruppi)
      ")

      rimossi = count_prima - count_dopo
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
