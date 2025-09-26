require 'sqlite3'

class Config
  def self.find(db, key)
    begin
      # Prima verifica se la tabella config esiste
      table_exists = db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='config'")
      return nil if table_exists.empty?
      
      result = db.execute("SELECT value FROM config WHERE key = ?", key)
      result.empty? ? nil : result.first[0]
    rescue SQLite3::Exception => e
      puts "Errore database config: #{e.message}"
      nil
    end
  end

  def self.save(db, key, value)
    begin
      # Crea la tabella se non esiste
      db.execute(<<-SQL
        CREATE TABLE IF NOT EXISTS config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      SQL
      )
      
      db.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", key, value)
      true
    rescue SQLite3::Exception => e
      puts "Errore salvataggio config: #{e.message}"
      false
    end
  end

  def self.setup_initial_config(db)
    # Configurazione iniziale
    initial_config = {
      'bot_name' => 'Bot Spesa',
      'version' => '1.0.0'
    }
    
    initial_config.each do |key, value|
      save(db, key, value)
    end
  end
end
