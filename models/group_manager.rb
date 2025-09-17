# models/group_manager.rb
require_relative '../db'

class GroupManager
  def self.crea_gruppo(bot, user_id, user_name)
    begin
      # Crea un nuovo gruppo virtuale
      DB.execute("INSERT INTO gruppi (nome, creato_da) VALUES (?, ?)", 
                ["Gruppo di #{user_name}", user_id])
      
      gruppo_id = DB.db.last_insert_row_id
      {success: true, gruppo_id: gruppo_id}
    rescue => e
      {success: false, error: e.message}
    end
  end

  def self.get_gruppo_by_chat_id(chat_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
  end

  def self.associa_gruppo_automaticamente(bot, chat_id, user_id)
  # Controlla whitelist
  unless Whitelist.is_allowed?(user_id)
    bot.api.send_message(
      chat_id: chat_id,
      text: "❌ Accesso negato. Solo utenti autorizzati possono associare gruppi."
    )
    return false
  end

  
    begin
      # Crea un nuovo gruppo e associalo alla chat
      DB.execute("INSERT INTO gruppi (nome, creato_da, chat_id) VALUES (?, ?, ?)", 
                ["Gruppo Chat", user_id, chat_id])
      
      gruppo_id = DB.db.last_insert_row_id
      
      bot.api.send_message(
        chat_id: chat_id,
        text: "🎉 Gruppo virtuale creato e associato! (ID: #{gruppo_id})\nUsa /lista per vedere la spesa."
      )
      
      true
    rescue => e
      puts "❌ Errore associazione gruppo: #{e.message}"
      false
    end
  end

# models/group_manager.rb
# models/group_manager.rb
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
end
