# models/whitelist.rb
require_relative '../db'

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

def self.add_user(user_id, username, full_name)
    DB.execute("INSERT OR REPLACE INTO whitelist (user_id, username, full_name, added_at) VALUES (?, ?, ?, CURRENT_TIMESTAMP)",
              [user_id, username, full_name])
  end

# models/whitelist.rb - aggiungi questo metodo


def self.salva_nome_utente(user_id, first_name, last_name)
  existing = DB.get_first_row("SELECT * FROM user_names WHERE user_id = ?", [user_id])
  
  if existing
    # ✅ USA INIZIALI ESISTENTI, non rigenerare!
    initials = existing['initials']
    puts "🔤 Utente esistente: #{first_name} #{last_name} -> #{initials} (conservate)"
    
    DB.execute("UPDATE user_names SET first_name = ?, last_name = ? WHERE user_id = ?",
               [first_name, last_name, user_id])
  else
    # Solo per nuovi utenti: genera iniziali
    initials = genera_iniziali_2_char(first_name, last_name)
    puts "🔤 Nuovo utente: #{first_name} #{last_name} -> #{initials}"
    
    DB.execute("INSERT INTO user_names (user_id, first_name, last_name, initials) VALUES (?, ?, ?, ?)",
               [user_id, first_name, last_name, initials])
  end
end

def self.ensure_user_name(user_id, first_name, last_name = nil)
  # Cerca utente esistente
  existing = DB.get_first_row("SELECT * FROM user_names WHERE user_id = ?", [user_id])
  
  if existing
    puts "✅ Utente già presente: #{existing['first_name']} #{existing['last_name']} -> #{existing['initials']}"
    # ✅ USA LE INIZIALI ESISTENTI, non rigenerare!
    return existing['initials']
  else
    # Solo per nuovi utenti: genera iniziali
    initials = genera_iniziali_2_char(first_name, last_name)
    DB.execute("INSERT INTO user_names (user_id, first_name, last_name, initials) VALUES (?, ?, ?, ?)",
               [user_id, first_name, last_name, initials])
    puts "🆕 Nuovo utente: #{first_name} #{last_name} -> #{initials}"
    return initials
  end
end

def self.genera_iniziali_2_char(first_name, last_name)
  return "US" unless first_name
  
  nome_completo = "#{first_name}#{last_name}".gsub(/\s+/, "").upcase
  return "US" if nome_completo.empty?
  
  # PRECARICA tutte le iniziali occupate
  iniziali_occupate = DB.execute("SELECT initials FROM user_names").map { |r| r['initials'] }
  
  # PRIORITÀ 1: INIZIALI NOME + COGNOME (se cognome esiste)
  if last_name && !last_name.strip.empty?
    tentative = "#{first_name[0]}#{last_name[0]}".upcase
    return tentative unless iniziali_occupate.include?(tentative)
  end
  
  # PRIORITÀ 2: PRIME 2 LETTERE DEL NOME
  if first_name.length >= 2
    tentative = first_name[0..1].upcase
    return tentative unless iniziali_occupate.include?(tentative)
  end
  
  # PRIORITÀ 3: LETTERE CONSECUTIVE DEL NOME COMPLETO
  (0..nome_completo.length-2).each do |i|
    tentative = nome_completo[i..i+1]
    return tentative unless iniziali_occupate.include?(tentative)
  end
  
  # PRIORITÀ 4: COMBINAZIONI ALTERNATIVE
  prima_lettera = first_name[0].upcase
  (1..nome_completo.length-1).each do |i|
    tentative = "#{prima_lettera}#{nome_completo[i]}"
    return tentative unless iniziali_occupate.include?(tentative)
  end
  
  "US"
end
  def self.approve_user(user_id, username, full_name)
    # Rimuovi dalla lista pending e aggiungi alla whitelist
    DB.execute("DELETE FROM pending_requests WHERE user_id = ?", [user_id])
    DB.execute("INSERT INTO whitelist (user_id, username, full_name) VALUES (?, ?, ?)",
              [user_id, username, full_name])
  end


  def self.is_creator?(user_id)
    creator_id = get_creator_id
    creator_id && creator_id == user_id
  end

  
end
