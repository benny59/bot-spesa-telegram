# handlers/message_handler.rb
# In alto al file aggiungi:
require_relative "../utils/keyboard_generator"
require_relative "../models/context"
require_relative "../db"

class MessageHandler
  # ==============================================================================
  # ROUTER PRINCIPALE (DISPATCHER)
  # ==============================================================================
  def self.route(bot, msg, context)
    # 1. Censimento (Nome corretto: aggiorna_membership)
    unless context.private_chat?
      DataManager.aggiorna_membership(msg.from.id, msg.chat.id) # riga 218 di db.rb
    end

    # 2. Scambio di Contesto
    if context.private_chat?
      # Usa il tuo metodo JSON a riga 331 di db.rb
      config_salvata = DataManager.carica_config_utente(msg.from.id)
      if config_salvata && config_salvata["target_g"]
        context.config["db_id"] = config_salvata["target_g"].to_i
        context.config["topic_id"] = (config_salvata["target_t"] || 0).to_i
      else
        # Se non c'è config, forza la Lista Personale per non perderla
        context.config["db_id"] = 0
        context.config["topic_id"] = 0
      end
    end

    # Gestione Foto (Ponte verso la logica esistente)
    if msg.photo && msg.photo.any?
      return self.handle_photo_bridge(bot, msg, context)
    end

    text = msg.text.to_s.strip
    puts "[ROUTING] 🚦 Smistamento: '#{text[0..20]}...' (Scope: #{context.scope})"

    case text
    when /^\/(start|help)/
      self.core_start(bot, context)
    when /^\+(.*)/
      # PILASTRO '+': Aggiunta articoli (Metodo Universale)
      self.core_aggiunta(bot, context, $1.to_s.strip)
    when /^\?(.*)/
      # PILASTRO '?': Ricerca/Storico
      self.core_mostra_lista(bot, context)
    when /^\*(.*)/
      # Shortcut Lista Personale (Forza gruppo 0)
      self.core_aggiunta_personale(bot, context, $1.to_s.strip)
    when "/private", "📋 MODALITÀ PRIVATA"
      self.core_cambio_modalita(bot, context)
    when "/miei", "📋 I MIEI ARTICOLI"
      # Richiama lo storico manager (Ponte)
      self.handle_myitems(bot, context, false)
    when "/cleanup"
      # Protezione di sistema
      self.core_cleanup(bot, context)
    else
      # Gestione delle risposte testuali alle Pending Actions
      self.handle_pending_responses(bot, msg, context)
    end
  end

  # ==============================================================================
  # FUNZIONI CORE (I PILASTRI)
  # ==============================================================================
  # In message_handler.rb, modifica core_mostra_lista
  # message_handler.rb

  # handlers/message_handler.rb

  def self.carica_contesto_privato(user_id, context)
    # Usiamo il tuo metodo esistente a riga 331 di db.rb
    config = DataManager.carica_config_utente(user_id)

    if config.is_a?(Hash) && config["target_g"]
      context.config["db_id"] = config["target_g"].to_i
      context.config["topic_id"] = (config["target_t"] || 0).to_i
    else
      # Default se non ha mai scelto nulla
      context.config["db_id"] = 0
      context.config["topic_id"] = 0
    end
  end

  def self.core_mostra_lista(bot, context, page = 0)
    g_db_id = context.config["target_g"] || 0
    t_id = context.config["target_t"] || 0

    if context.lista_personale?
      header = "🏠 Lista Personale"
    else
      # Recuperiamo il chat_id reale di Telegram per interrogare i topics
      g_info = DB.get_first_row("SELECT chat_id, nome FROM gruppi WHERE id = ?", [g_db_id])
      real_chat_id = g_info ? g_info["chat_id"] : 0
      nome_gruppo = g_info ? g_info["nome"] : "Gruppo"

      # Otteniamo il nome PURO dal DataManager
      nome_topic = DataManager.get_topic_name(real_chat_id, t_id)

      # Decidiamo qui come formattare la parola di chiarimento
      etichetta_topic = (t_id == 0) ? nome_topic : "Lista #{nome_topic}"
      header = "🎯 #{nome_gruppo}: #{etichetta_topic}"
    end

    items = DataManager.prendi_articoli_ordinati(g_db_id, t_id)
    ui = KeyboardGenerator.genera_lista(items, g_db_id, t_id, page, header)

    bot.api.send_message(
      chat_id: context.user_id,
      text: ui[:text],
      reply_markup: ui[:markup],
      parse_mode: "Markdown",
    )
  end

  def self.show_private_keyboard(bot, chat_id)
    puts "📟 [DEBUG] Visualizzazione tastiera privata per: #{chat_id}"

    markup = KeyboardGenerator.tastiera_privata_fissa

    bot.api.send_message(
      chat_id: chat_id,
      text: "🎮 *Pannello di Controllo*\nUsa i tasti in basso per gestire la spesa.",
      reply_markup: markup,
      parse_mode: "Markdown",
    )
  end

  def self.core_cambio_modalita(bot, context)
    # Nome corretto del metodo presente in db.rb a riga 231
    destinazioni = DataManager.prendi_destinazioni_censite(context.user_id)
    markup = KeyboardGenerator.tastiera_scelta_gruppo(destinazioni)

    bot.api.send_message(
      chat_id: context.chat_id,
      text: "🎯 *Seleziona Destinazione*\nDove vuoi inviare i prodotti?",
      reply_markup: markup,
      parse_mode: "Markdown",
    )
  end

  # CORE AGGIUNTA (+)
  def self.core_aggiunta(bot, context, contenuto)
    if contenuto.empty?
      DataManager.set_pending(chat_id: context.chat_id, topic_id: context.topic_id, action: "add:veloce")
      bot.api.send_message(chat_id: context.chat_id, text: "✍️ Cosa aggiungo?")
    else
      g_id = context.lista_personale? ? 0 : (context.config["db_id"] || 0)
      t_id = context.lista_personale? ? 0 : (context.config["topic_id"] || 0)

      DataManager.aggiungi_articoli(gruppo_id: g_id, user_id: context.user_id, items_text: contenuto, topic_id: t_id)

      # Refresh automatico della lista dopo l'aggiunta
      self.core_mostra_lista(bot, context)
    end
  end

  # CORE STORICO (?)
  def self.core_storico(bot, context, query)
    puts "[CORE] 🔍 Esecuzione Ricerca (?)"
    g_id = context.lista_personale? ? 0 : (context.config["db_id"] || 0)
    t_id = context.lista_personale? ? 0 : (context.config["topic_id"] || 0)

    risultati = DataManager.ricerca_storico(gruppo_id: g_id, topic_id: t_id, query: query.empty? ? nil : query)

    if risultati.any?
      testo = "📜 **Storico / Suggerimenti:**\n" + risultati.map { |r| "• #{r["nome"]} (#{r["conteggio"]})" }.join("\n")
      bot.api.send_message(chat_id: context.chat_id, text: testo, parse_mode: "Markdown")
    else
      bot.api.send_message(chat_id: context.chat_id, text: "❓ Storico vuoto.")
    end
  end

  # CORE SHORTCUT PERSONALE (*)
  def self.core_aggiunta_personale(bot, context, contenuto)
    DataManager.aggiungi_articoli(gruppo_id: 0, user_id: context.user_id, items_text: contenuto, topic_id: 0)
    # Mostra la lista personale (G:0)
    self.core_mostra_lista(bot, context)
  end

  # ==============================================================================
  # METODI PONTE E FALLBACK
  # ==============================================================================
  def self.mostra_lista(bot, context, gruppo_id, topic_id, page = 0)
    # 1. Recupero dati dal Monitor DB
    items = DB.execute("SELECT * FROM items WHERE gruppo_id = ? AND topic_id = ? ORDER BY creato_il DESC", [gruppo_id, topic_id])
    nome_gruppo = (gruppo_id == 0) ? "Lista Personale" : "Gruppo #{gruppo_id}"

    # 2. Generazione UI tramite il modulo Keyboard
    ui = KeyboardGenerator.genera_lista(items, gruppo_id, topic_id, page, nome_gruppo)

    # 3. Invio (Gestendo correttamente il thread_id per i gruppi)
    t_id = context.private_chat? ? nil : (context.topic_id || topic_id)

    bot.api.send_message(
      chat_id: context.chat_id,
      message_thread_id: t_id,
      text: ui[:text],
      reply_markup: ui[:markup],
      parse_mode: "Markdown",
    )
  end

  def self.handle_pending_responses(bot, msg, context)
    pending = DataManager.ottieni_pending(context.chat_id, context.topic_id)
    if pending
      self.core_aggiunta(bot, context, msg.text)
      DataManager.clear_pending(chat_id: context.chat_id, topic_id: context.topic_id)
    end
  end

  def self.handle_photo_bridge(bot, msg, context)
    puts "[BRIDGE] 📸 Delega gestione foto a legacy handler"
    # Qui chiameremo il vecchio handle_photo_message o handle_private_photo
    # Per ora logghiamo solo per non crashare
  end

  def self.core_start(bot, context)
    bot.api.send_message(chat_id: context.chat_id, text: "🤖 **Bot Spesa Refactored**\nUsa `+` per aggiungere o `?` per cercare.")
  end

  def self.core_cleanup(bot, context)
    # Esempio di metodo protetto
    return unless context.user_id.to_s == "IL_TUO_ID_ADMIN"
    puts "[CORE] 🧹 Avvio Cleanup di sistema"
  end
end
