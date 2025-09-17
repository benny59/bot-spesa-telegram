# models/whitelist.rb
require_relative '../db'

# models/whitelist.rb
class Whitelist
  def self.is_allowed?(user_id)  # CORREGGI: is_allowed? invece di is_allowed?
    count = DB.get_first_value("SELECT COUNT(*) FROM whitelist")
    return true if count == 0  # Se whitelist vuota, permetti a tutti (primo utente diventa creatore)
    
    DB.get_first_value("SELECT COUNT(*) FROM whitelist WHERE user_id = ?", [user_id]) > 0
  end

  def self.get_creator_id
    # Restituisce l'ID del primo utente aggiunto (il creatore)
    creator = DB.get_first_row("SELECT user_id FROM whitelist ORDER BY added_at LIMIT 1")
    creator ? creator['user_id'] : nil
  end

  def self.add_creator(user_id, username, full_name)
    # Aggiungi il primo utente come creatore
    DB.execute("INSERT OR REPLACE INTO whitelist (user_id, username, full_name) VALUES (?, ?, ?)",
              [user_id, username, full_name])
  end

  def self.add_pending_request(user_id, username, full_name)
    DB.execute("INSERT OR REPLACE INTO pending_requests (user_id, username, full_name) VALUES (?, ?, ?)",
              [user_id, username, full_name])
  end

  def self.get_pending_requests
    DB.execute("SELECT * FROM pending_requests ORDER BY requested_at")
  end

  def self.remove_pending_request(user_id)
    DB.execute("DELETE FROM pending_requests WHERE user_id = ?", [user_id])
  end
  
    def self.all_users
    DB.execute("SELECT * FROM whitelist ORDER BY full_name")
  end

# models/whitelist.rb - aggiungi questo metodo
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


  def self.is_creator?(user_id)
    creator_id = get_creator_id
    creator_id && creator_id == user_id
  end

  
end
