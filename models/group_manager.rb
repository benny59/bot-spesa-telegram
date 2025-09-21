# models/group_manager.rb
require_relative '../db'
require_relative 'whitelist'  # Aggiungi questa linea

class GroupManager
  def self.crea_gruppo(bot, user_id, user_name)
    begin
      puts "🔍 Creazione gruppo per: #{user_name} (ID: #{user_id})"
      
      # Crea un nuovo gruppo virtuale
      DB.execute("INSERT INTO gruppi (nome, creato_da) VALUES (?, ?)", 
                ["Gruppo di #{user_name}", user_id])
      
      gruppo_id = DB.db.last_insert_row_id
      puts "✅ Gruppo creato con ID: #{gruppo_id}"
      
      {success: true, gruppo_id: gruppo_id}
    rescue => e
      puts "❌ Errore creazione gruppo: #{e.message}"
      {success: false, error: e.message}
    end
  end
  


  def self.associa_gruppo_automaticamente(bot, chat_id, user_id)
    begin
      puts "🔍 Associazione gruppo per chat: #{chat_id}, utente: #{user_id}"
      
      # Controlla whitelist prima di associare
      unless Whitelist.is_allowed?(user_id)
        puts "❌ Utente non autorizzato per associazione gruppo"
        bot.api.send_message(
          chat_id: chat_id,
          text: "❌ Accesso negato. Solo utenti autorizzati possono associare gruppi."
        )
        return false
      end

      # Cerca se esiste già un gruppo senza chat_id per questo utente
      gruppo_esistente = DB.get_first_row("SELECT * FROM gruppi WHERE creato_da = ? AND chat_id IS NULL ORDER BY id DESC LIMIT 1", [user_id])
      
      if gruppo_esistente
        # Assoccia il gruppo esistente
        puts "✅ Trovato gruppo esistente ID: #{gruppo_esistente['id']} da associare"
        DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [chat_id, gruppo_esistente['id']])
        gruppo_id = gruppo_esistente['id']
        messaggio = "🎉 Gruppo virtuale associato! (ID: #{gruppo_id})"
      else
        # Crea un nuovo gruppo
        puts "🔍 Nessun gruppo esistente, creo nuovo gruppo"
        DB.execute("INSERT INTO gruppi (nome, creato_da, chat_id) VALUES (?, ?, ?)", 
                  ["Gruppo Chat", user_id, chat_id])
        gruppo_id = DB.db.last_insert_row_id
        messaggio = "🎉 Nuovo gruppo virtuale creato! (ID: #{gruppo_id})"
      end
      
      bot.api.send_message(
        chat_id: chat_id,
        text: "#{messaggio}\nUsa /lista per vedere la spesa."
      )
      
      puts "✅ Gruppo associato con ID: #{gruppo_id}"
      true
    rescue => e
      puts "❌ Errore associazione gruppo: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore nella creazione del gruppo. Riprova più tardi."
      )
      false
    end
  end

 def self.find_or_migrate_group(chat_id, title)
    gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])

    if !gruppo && chat_id.to_s.start_with?("-100")
      # provo a cercare col vecchio formato
      old_chat_id = chat_id.to_s.sub("-100", "-").to_i
      gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [old_chat_id])

      if gruppo
        # aggiorno al nuovo chat_id
        DB.execute("UPDATE gruppi SET chat_id = ?, nome = ? WHERE id = ?",
                   [chat_id, title, gruppo['id']])
        gruppo['chat_id'] = chat_id
        gruppo['nome'] = title
      end
    end

    gruppo
  end

  def self.get_gruppo_by_chat_id(chat_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
  end

  def self.salva_nome_utente(user_id, first_name, last_name)
    # Calcola le iniziali correttamente
    initials = if first_name && last_name && !last_name.to_s.empty?
                 "#{first_name[0]}#{last_name[0]}".upcase
               elsif first_name && !first_name.to_s.empty?
                 first_name[0].upcase
               else
                 "U"
               end

    # Forza l'aggiornamento anche se l'utente esiste già
    DB.execute("INSERT OR REPLACE INTO user_names (user_id, first_name, last_name, initials) VALUES (?, ?, ?, ?)",
              [user_id, first_name, last_name, initials])
    
    # Log per debug
    puts "👤 Utente salvato: #{first_name} #{last_name} -> #{initials}"
  end


  def self.pulizia_gruppi_orfani
    orfani = DB.execute("SELECT * FROM gruppi WHERE chat_id IS NULL")
    puts "🗑️ Trovati #{orfani.size} gruppi orfani"
    
    DB.execute("DELETE FROM gruppi WHERE chat_id IS NULL")
    puts "✅ Gruppi orfani eliminati"
  end
end
