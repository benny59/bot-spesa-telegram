# models/group_manager.rb
require_relative "../db"
require_relative "whitelist"  # Aggiungi questa linea

class GroupManager
  def self.get_gruppo_by_chat_id(chat_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
  end

  def self.find_pending_by_user(user_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id IS NULL AND creato_da = ?", [user_id])
  end

  def self.update_chat_id(group_id, chat_id, title)
    #    DB.execute("UPDATE gruppi SET chat_id = ?, nome = ? WHERE id = ?", [chat_id, title, group_id])
    DB.execute(
      "UPDATE gruppi SET chat_id = ?, nome = ?, topic_id = ? WHERE id = ?",
      [chat_id, msg.chat.title, msg.message_thread_id, gruppo_in_attesa["id"]]
    )
  end

  def self.find_by_chat_id(chat_id)
    DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
  end

  def self.notifiche_operazioni_abilitate?(gruppo_id)
    DB.get_first_value(
      "SELECT notifiche_operazioni FROM gruppi WHERE id = ?",
      [gruppo_id]
    ).to_i == 1
  end

  def self.imposta_notifiche_operazioni(gruppo_id, abilitate)
    DB.execute(
      "UPDATE gruppi SET notifiche_operazioni = ? WHERE id = ?",
      [abilitate ? 1 : 0, gruppo_id]
    )
  end

  def self.admin_del_gruppo?(bot, chat_id, user_id)
    member = bot.api.get_chat_member(chat_id: chat_id, user_id: user_id)
    %w[creator administrator].include?(member.status)
  rescue Telegram::Bot::Exceptions::ResponseError => e
    puts "⚠️ [GROUP] Impossibile verificare i permessi: #{e.message}"
    false
  end

  def self.crea_gruppo(bot, user_id, user_name)
    DB.execute("INSERT INTO gruppi (nome, creato_da, chat_id) VALUES (?, ?, ?)",
               ["Gruppo di #{user_name}", user_id, nil])  # ← chat_id esplicitamente NULL
    gruppo_id = DB.db.last_insert_row_id
    puts "✅ Gruppo in attesa creato con ID: #{gruppo_id} (chat_id: NULL)"
    { success: true, gruppo_id: gruppo_id }
  end

  def self.associa_gruppo_automaticamente(bot, chat_id, user_id)
    begin
      puts "🔍 Associazione gruppo per chat: #{chat_id}, utente: #{user_id}"

      # Controlla whitelist prima di associare
      unless Whitelist.is_allowed?(user_id)
        puts "❌ Utente non autorizzato per associazione gruppo"
        bot.api.send_message(
          chat_id: chat_id,
          text: "❌ Accesso negato. Solo utenti autorizzati possono associare gruppi.",
        )
        return false
      end

      # Cerca se esiste già un gruppo senza chat_id per questo utente
      gruppo_esistente = DB.get_first_row("SELECT * FROM gruppi WHERE creato_da = ? AND chat_id IS NULL ORDER BY id DESC LIMIT 1", [user_id])

      if gruppo_esistente
        # Assoccia il gruppo esistente
        puts "✅ Trovato gruppo esistente ID: #{gruppo_esistente["id"]} da associare"
        DB.execute("UPDATE gruppi SET chat_id = ? WHERE id = ?", [chat_id, gruppo_esistente["id"]])
        gruppo_id = gruppo_esistente["id"]
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
        text: "#{messaggio}\nUsa /lista per vedere la spesa.",
      )

      puts "✅ Gruppo associato con ID: #{gruppo_id}"
      true
    rescue => e
      puts "❌ Errore associazione gruppo: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        text: "❌ Errore nella creazione del gruppo. Riprova più tardi.",
      )
      false
    end
  end

  def self.find_or_migrate_group(chat_id, titolo = nil, user_id = nil)
    gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])

    unless gruppo
      # Se non esiste, CERCA prima gruppi in attesa
      if user_id
        gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id IS NULL AND creato_da = ?", [user_id])
        if gruppo
          # Accoppiamento
          DB.execute("UPDATE gruppi SET chat_id = ?, nome = ? WHERE id = ?",
                     [chat_id, titolo || gruppo["nome"], gruppo["id"]])
          gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE id = ?", [gruppo["id"]])
          puts "✅ Gruppo accoppiato: #{gruppo["id"]}"
          return gruppo
        end
      end

      # Solo se non ci sono gruppi in attesa, creane uno nuovo
      DB.execute("INSERT INTO gruppi (chat_id, nome, creato_da) VALUES (?, ?, ?)",
                 [chat_id, titolo || "Gruppo Chat", user_id || 0])
      gruppo = DB.get_first_row("SELECT * FROM gruppi WHERE chat_id = ?", [chat_id])
      puts "🆕 Nuovo gruppo creato: #{gruppo["id"]}"
    end

    gruppo
  end

  def self.pulizia_gruppi_orfani
    orfani = DB.execute("SELECT * FROM gruppi WHERE chat_id IS NULL")
    puts "🗑️ Trovati #{orfani.size} gruppi orfani"

    DB.execute("DELETE FROM gruppi WHERE chat_id IS NULL")
    puts "✅ Gruppi orfani eliminati"
  end
end
