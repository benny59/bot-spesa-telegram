# handlers/message_handler.rb

require_relative "storico_manager"
require_relative "../models/pending_action"
require_relative "../models/context"
require "json" # Necessario per il parsing della config

class MessageHandler
  def self.route(bot, msg, context)
    text = msg.text.to_s.strip

    case
    when context.private_chat?
      route_private(bot, msg, context)
    when context.group_chat?
      route_group(bot, msg, context)
    else
      log_unhandled(context, "chat_type sconosciuto")
    end
  end

  # =============================
  # PRIVATE CHAT
  # =============================
  def self.route_private(bot, msg, context)
    # Caricamento configurazione (quello che vedi nel log)
    config_row = DB.get_first_row("SELECT value FROM config WHERE key = ?", ["context:#{context.user_id}"])
    config = config_row ? JSON.parse(config_row["value"]) : nil

    # DEBUG (già presente nei tuoi log)
    if config
      puts "DEBUG CONFIG FOUND: #{config.inspect}"
    end

    case msg.text
    when /^\/start$/
      handle_start(bot, context)
    when "/private"
      Context.show_group_selector(bot, context.user_id)
    when "?"
      if config
        # Mostra la lista usando i dati del gruppo selezionato
        puts "DEBUG ACTION: Genero lista per #{config["db_id"]}"
        KeyboardGenerator.genera_lista(
          bot,
          context.chat_id,   # Chat privata
          config["db_id"],   # Gruppo da cui leggere
          context.user_id,
          nil,
          0,
          config["topic_id"], # Filtra per il reparto (es. Topic 2)
          0 # <-- Invia nel thread 0 (cioè nessuno) della chat privata
        )
      else
        bot.api.send_message(chat_id: context.chat_id, text: "❌ Seleziona prima un gruppo con /private")
      end
    when /^\+(.+)?/
      if config
        # Gestione aggiunta articoli (usa il metodo che abbiamo creato prima)
        process_private_add(bot, context, config, msg.text[1..].to_s.strip, msg.from.first_name)
      else
        bot.api.send_message(chat_id: context.chat_id, text: "❌ Seleziona prima un gruppo con /private")
      end
    else
      # Gestione delle risposte testuali se c'è un'azione pendente (es. dopo aver premuto + vuoto)
      handle_private_pending(bot, msg, context, config)
    end
  end

  # =============================
  # METODI DI SUPPORTO PRIVATI
  # =============================

  def self.handle_plus_in_private(bot, msg, context, gruppo_id, target_topic_id, nome_gruppo)
    raw = msg.text[1..].to_s.strip
    user_name = msg.from.first_name

    if raw.empty?
      # Inizia azione pendente salvando anche il topic
      DB.execute(
        "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
        [context.chat_id, "add:#{user_name}", gruppo_id, target_topic_id]
      )
      bot.api.send_message(chat_id: context.chat_id, text: "📝 [#{nome_gruppo}] Scrivi gli articoli per il topic #{target_topic_id}:")
    else
      # Esegui aggiunta diretta
      process_private_add(bot, context, gruppo_id, target_topic_id, raw, user_name, nome_gruppo)
    end
  end

  # Metodo centralizzato per aggiungere e notificare
  # handlers/message_handler.rb
  def self.process_private_add(bot, context, config, items_text, user_name)
    if items_text.empty?
      # Se ha scritto solo "+", attiviamo la PendingAction
      DB.execute(
        "INSERT OR REPLACE INTO pending_actions (chat_id, topic_id, action, gruppo_id) VALUES (?, ?, ?, ?)",
        [context.chat_id, 0, "add:#{user_name}", config["db_id"]]
      )
      bot.api.send_message(chat_id: context.chat_id, text: "✍️ Scrivi gli articoli per **#{config["topic_name"]}**:")
    else
      # Aggiunta diretta
      Lista.aggiungi(config["db_id"], context.user_id, items_text, config["topic_id"])

      # NOTIFICA AL GRUPPO (Usando il CHAT_ID negativo)
      begin
        bot.api.send_message(
          chat_id: config["chat_id"],
          message_thread_id: (config["topic_id"] == 0 ? nil : config["topic_id"]),
          text: "🛒 #{user_name} ha aggiunto da privato:\n#{items_text}",
        )
      rescue => e
        puts "❌ Errore notifica gruppo: #{e.message}"
      end

      bot.api.send_message(chat_id: context.chat_id, text: "✅ Aggiunto a #{config["topic_name"]}!")
      KeyboardGenerator.genera_lista(bot, context.chat_id, config["db_id"], context.user_id, nil, 0, config["topic_id"])
    end
  end

  def self.handle_private_pending(bot, msg, context, config)
    # 1. Recupera l'azione pendente
    pending = PendingAction.fetch(chat_id: context.chat_id, topic_id: 0)

    if pending && pending["action"].to_s.start_with?("add:") && config && config["db_id"]
      user_name = msg.from.first_name
      items_text = msg.text.strip
      return if items_text.empty?

      # 2. Aggiungi gli articoli al database
      Lista.aggiungi(config["db_id"], context.user_id, items_text, config["topic_id"] || 0)

      # 3. NOTIFICA AL GRUPPO (Questa è la parte che mancava!)
      begin
        # Usiamo il chat_id reale del gruppo salvato nella config
        target_chat_id = config["chat_id"]
        target_topic_id = config["topic_id"] == 0 ? nil : config["topic_id"]

        bot.api.send_message(
          chat_id: target_chat_id,
          message_thread_id: target_topic_id,
          text: "🛒 #{user_name} ha aggiunto da privato:\n#{items_text}",
        )
        puts "✅ Notifica inviata al gruppo #{target_chat_id}"
      rescue => e
        puts "❌ Errore notifica gruppo: #{e.message}"
      end

      # 4. Pulisci l'azione e conferma all'utente
      PendingAction.clear(chat_id: context.chat_id, topic_id: 0)
      bot.api.send_message(chat_id: context.chat_id, text: "✅ Articoli aggiunti a **#{config["topic_name"]}**!")

      # Aggiorna l'interfaccia privata
      KeyboardGenerator.genera_lista(bot, context.chat_id, config["db_id"], context.user_id, nil, 0, config["topic_id"] || 0)
    else
      log_unhandled(context, "private: #{msg.text}")
    end
  end

  # =============================
  # GROUP / SUPERGROUP
  # =============================
  def self.route_group(bot, msg, context)
    gruppo = GroupManager.get_gruppo_by_chat_id(context.chat_id)
# ✅ AGGIORNAMENTO SILENZIOSO NOME TOPIC
    # Ogni volta che arriva un messaggio, se Telegram ci passa i metadati del topic, lo salviamo
    TopicManager.update_from_msg(msg)
    case msg.text

    when /^\+(.+)?/
      raw = msg.text[1..].to_s.strip

      if raw.empty?
        PendingAction.start_add(context, gruppo)
      else
        process_add_items(
          bot: bot,
          text: raw,
          context: context,
          gruppo: gruppo,
        )
      end
    when "?"
      topic_id = msg.message_thread_id || 0

      # mostra la lista corrente (help implicito)
      KeyboardGenerator.genera_lista(
        bot,
        context.chat_id,
        gruppo["id"],
        context.user_id,
        nil,
        0,
        topic_id
      )
      return
    when "/private"
      if context.scope == "group"
        ContextManager.activate_private_for_group(context)
      end
    else
      pending = PendingAction.fetch(
        chat_id: context.chat_id,
        topic_id: context.topic_id,
      )

      return unless pending
      return unless pending["action"].start_with?("add:")

      items_text = msg.text.strip
      return if items_text.empty?

      Lista.aggiungi(
        pending["gruppo_id"],
        context.user_id,
        items_text,
        context.topic_id
      )

      PendingAction.clear(
        chat_id: context.chat_id,
        topic_id: context.topic_id,
      )

      KeyboardGenerator.genera_lista(
        bot,
        context.chat_id,
        pending["gruppo_id"],
        context.user_id,
        nil,
        0,
        context.topic_id
      )
    end
  end
  # =============================
  # STUB (volutamente vuoti)
  # =============================
  def self.handle_start(bot, context)
    bot.api.send_message(
      chat_id: context.chat_id,
      text: "👋 Bot avviato",
    )
  end

  def self.handle_newgroup(bot, context)
    # TODO: spostare in GroupManager
    raise NotImplementedError, "handle_newgroup da implementare"
  end

  def self.process_add_items(bot:, text:, context:, gruppo:)
    return if text.nil? || text.strip.empty?

    topic_id = context.topic_id || 0
    user_id = context.user_id

    items_text = text.strip
    items = items_text.split(",").map(&:strip).reject(&:empty?)

    return if items.empty?

    Lista.aggiungi(gruppo["id"], user_id, items_text, topic_id)

    items.each do |articolo|
      StoricoManager.aggiorna_da_aggiunta(articolo, gruppo["id"], topic_id)
    end

    bot.api.send_message(
      chat_id: context.chat_id,
      message_thread_id: topic_id,
      text: "✅ #{items.count} articolo(i) aggiunti: #{items.join(", ")}",
    )

    KeyboardGenerator.genera_lista(
      bot,
      context.chat_id,
      gruppo["id"],
      user_id,
      nil,
      0,
      topic_id
    )

    notifica_gruppo(bot, gruppo_id, topic_id, user_name, items)
  end

  def self.handle_private_mode(bot, context)
    # TODO: gestione sessione privata
    puts "🔒 PRIVATE MODE richiesto da user #{context.user_id}"
  end

  # handlers/message_handler.rb

  def self.log_unhandled(context, msg)
    # Usa context.scope invece di chat_type
    puts "⚠️ UNHANDLED [#{context.scope}] #{msg}"
  end

  def self.notifica_gruppo(bot, gruppo_id, topic_id, user_name, items)
    puts "📢 Tentativo notifica: Gruppo #{gruppo_id}, Topic #{topic_id}"

    begin
      bot.api.send_message(
        chat_id: gruppo_id,
        message_thread_id: (topic_id == 0 ? nil : topic_id),
        text: "🛒 **#{user_name}** ha aggiunto da privato:\n#{items}",
      )
      puts "✅ Notifica inviata correttamente."
    rescue => e
      puts "❌ Errore invio notifica: #{e.message}"
      # Se l'errore è 'thread not found', il topic_id potrebbe essere errato
      # Se l'errore è 'chat not found', il bot potrebbe essere stato rimosso
    end
  end

  def self.handle_plus_command(bot, msg, chat_id, user_id, gruppo)
    if gruppo.nil?
      bot.api.send_message(chat_id: chat_id, text: "❌ Nessuna lista attiva. Usa /newgroup in chat privata.")
      return
    end

    # MODIFICA: Ottieni il topic_id dal messaggio
    topic_id = msg.message_thread_id || 0

    begin
      text = msg.text.strip

      # Gestione PRIORITARIA di +? (help)
      if text == "+?"
        bot.api.send_message(
          chat_id: chat_id,
          text: "📋 <b>Help comando +</b>\n\n" \
                "• <code>+</code> - Mostra prompt aggiunta articoli\n" \
                "• <code>+ articolo</code> - Aggiungi un articolo\n" \
                "• <code>+ art1, art2, art3</code> - Aggiungi multiple articoli\n" \
                "• <code>+?</code> - Mostra questo help",
          parse_mode: "HTML",
        )
        return
      end

      # Se c'è testo dopo il + (escluso il caso +? già gestito)
      if text.length > 1
        items_text = text[1..-1].strip
        if items_text.empty?
          # Solo + senza testo
          DB.execute(
            "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
            [chat_id, "add:#{msg.from.first_name}", gruppo["id"], topic_id]
          )
          bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
        else
          # + seguito da testo - MODIFICA: Passa topic_id a Lista.aggiungi
          Lista.aggiungi(gruppo["id"], user_id, items_text, topic_id)
          added_items = items_text.split(",").map(&:strip)
          added_count = added_items.count
          added_items.each do |articolo|
            StoricoManager.aggiorna_da_aggiunta(articolo.strip, gruppo["id"], topic_id)
          end

          bot.api.send_message(
            chat_id: chat_id,
            message_thread_id: topic_id,
            text: "✅ #{msg.from.first_name} ha aggiunto #{added_count} articolo(i): #{added_items.join(", ")}",
          )
          # MODIFICA: Aggiorna la lista passando topic_id
          KeyboardGenerator.genera_lista(bot, chat_id, gruppo["id"], user_id, nil, 0, topic_id)
        end
      else
        # Solo +
        DB.execute(
          "INSERT OR REPLACE INTO pending_actions (chat_id, action, gruppo_id, topic_id) VALUES (?, ?, ?, ?)",
          [chat_id, "add:#{msg.from.first_name}", gruppo["id"], topic_id]
        )
        bot.api.send_message(chat_id: chat_id, text: "✍️ #{msg.from.first_name}, scrivi gli articoli separati da virgola:")
      end
    rescue => e
      puts "❌ Errore nel comando +: #{e.message}"
      bot.api.send_message(
        chat_id: chat_id,
        message_thread_id: topic_id,
        text: "❌ Errore nell'aggiunta degli articoli",
      )
    end
  end
end
class TopicManager
  def self.update_from_msg(msg)
    chat_id = msg.chat.id
    topic_id = msg.message_thread_id || 0
    topic_name = nil

    # Caso 0: Topic Generale (non ha eventi forum_topic_created)
    if topic_id == 0
      # Verifichiamo se esiste già, altrimenti mettiamo il default
      exists = DB.get_first_value("SELECT 1 FROM topics WHERE chat_id = ? AND topic_id = 0", [chat_id])
      topic_name = "Generale" unless exists
    # Caso A: Messaggio di servizio creazione topic (ID > 0)
    elsif msg.forum_topic_created
      topic_name = msg.forum_topic_created.name
    # Caso B: Messaggio di servizio modifica topic
    elsif msg.forum_topic_edited
      topic_name = msg.forum_topic_edited.name
    # Caso C: Metadati nel reply
    elsif msg.respond_to?(:reply_to_message) && msg.reply_to_message&.forum_topic_created
      topic_name = msg.reply_to_message.forum_topic_created.name
    end

    return if topic_name.nil?

    DB.execute(
      "INSERT OR REPLACE INTO topics (chat_id, topic_id, nome) VALUES (?, ?, ?)",
      [chat_id, topic_id, topic_name]
    )
    puts "🏷️ Topic censito: #{topic_name} (ID: #{topic_id})"
  end
end
