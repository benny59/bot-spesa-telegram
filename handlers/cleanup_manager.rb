# handlers/cleanup_manager.rb
class CleanupManager
  # ========================================
  # 🧹 CLEANUP COMPLETO
  # ========================================
  def self.esegui_cleanup(bot, chat_id, user_id)
    unless Whitelist.get_creator_id == user_id
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Solo il creatore può eseguire il cleanup.",
      )
      return
    end

    begin
      risultati = {
        pending_actions: pulisci_pending_actions_orfane(),
        storico_articoli: pulisci_storico_vecchio(),
        items_orfani: pulisci_items_orfani(),
      }

      # 📋 REPORT FINALE
      messaggio_riepilogo = genera_riepilogo_cleanup(risultati)

      bot.api.send_message(
        chat_id: chat_id,
        text: messaggio_riepilogo,
        parse_mode: "Markdown",
      )
    rescue => e
      puts "❌ Errore durante cleanup: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore durante il cleanup: #{e.message}",
      )
    end
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
    # Ottieni le statistiche PRIMA del cleanup (dove possibile)
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

    <<~TEXT
      🧹 *CLEANUP COMPLETATO*

      📊 *Risultati della pulizia:*
      • 🗑️ Pending actions (>24h): #{stats_pre[:pending_actions_vecchie]} → rimosse: #{risultati[:pending_actions]}
      • 📊 Articoli storico (vecchi): #{stats_pre[:storico_vecchio]} → rimossi: #{risultati[:storico_articoli]}
      • 🗂️ Items orfani: #{stats_pre[:items_orfani]} → rimossi: #{risultati[:items_orfani]}

      ✅ #{risultati.values.sum > 0 ? "Database pulito!" : "Database già ottimizzato!"}
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
