# whitelist_manager.rb
require_relative 'db'
require_relative 'models/whitelist'

class WhitelistManager
  def self.setup_initial_whitelist
    # Aggiungi qui gli user_id degli utenti autorizzati
    authorized_users = [
      [238095683, 'hass_ben', 'Marco Benatti']  # Sostituisci con i tuoi dati
    ]

    authorized_users.each do |user_id, username, full_name|
      Whitelist.add_user(user_id, username, full_name)
      puts "✅ Aggiunto alla whitelist: #{full_name} (@#{username})"
    end

    puts "📋 Whitelist inizializzata con #{authorized_users.size} utenti"
  end
end

# Esegui per inizializzare la whitelist
if __FILE__ == $0
  WhitelistManager.setup_initial_whitelist
end
