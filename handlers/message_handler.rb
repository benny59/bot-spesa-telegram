# handlers/message_handler.rb
# In alto al file aggiungi:
require_relative "../utils/keyboard_generator"
require_relative "../models/context"
require_relative "../db"

class MessageHandler
  # ==============================================================================
  # ROUTER PRINCIPALE (DISPATCHER)
def self.route(bot, msg, context)
    u_id = msg.from.id
    g_chat_id = msg.chat.id
    scope = context.scope
    
    # 1. Censimento
    unless context.private_chat?
      puts "[ROUTING] 👥 Gruppo rilevato. Aggiorno membership per U:#{u_id} in G:#{g_chat_id}"
      DataManager.aggiorna_membership(u_id, g_chat_id)
    end

    # 2. Scambio di Contesto (Cruciale per i target)
if context.private_chat?
      puts "[ROUTING] 🏠 Chat Privata: Carico config target..."
      config_salvata = DataManager.carica_config_utente(u_id)
      if config_salvata && config_salvata["target_g"]
        context.config["db_id"] = config_salvata["target_g"].to_i
        context.config["topic_id"] = (config_salvata["target_t"] || 0).to_i
        puts "[ROUTING] 🎯 Target impostato: G:#{context.config["db_id"]} T:#{context.config["topic_id"]}"
      else
        context.config["db_id"] = 0
        context.config["topic_id"] = 0
        puts "[ROUTING] 👤 Nessun target: uso Lista Personale"
      end
    else
# --- AGGIUNTA PER I GRUPPI ---
      # Se siamo in un gruppo, dobbiamo usare l'id del database associato a questo chat_id
      # e il topic_id reale del messaggio corrente.
      g_db_id = DB.get_first_value("SELECT id FROM gruppi WHERE chat_id = ?", [g_chat_id]) || 0
      context.config["db_id"] = g_db_id
      context.config["topic_id"] = (msg.message_thread_id || 0).to_i
      puts "[ROUTING] 🏢 Chat di Gruppo: G:#{context.config["db_id"]} T:#{context.config["topic_id"]}"
          end

    # Gestione Foto
    if msg.photo && msg.photo.any?
      puts "[ROUTING] 📸 Ricevuta Foto. Smisto a handle_photo_bridge"
      return self.handle_photo_bridge(bot, msg, context)
    end

    text = msg.text.to_s.strip
    puts "[ROUTING] 🚦 Smistamento: '#{text[0..20]}...' (Scope: #{scope})"

    case text
    when /^\/(start|help)/
      puts "[ROUTING] ✅ Comando Start/Help rilevato"
      self.core_start(bot, context)
    when /^\+(.*)/
      payload = $1.to_s.strip
      puts "[ROUTING] ✅ Comando '+' rilevato. Payload: '#{payload}'"
      self.core_aggiunta(bot, context, payload)
    when /^\?(.*)/
      puts "[ROUTING] ✅ Comando '?' rilevato. Mostro lista"
      self.core_mostra_lista(bot, context)
    when /^\*(.*)/
      payload = $1.to_s.strip
      puts "[ROUTING] ✅ Comando '*' rilevato. Aggiunta personale: '#{payload}'"
      self.core_aggiunta_personale(bot, context, payload)
    when "/private", "📋 MODALITÀ PRIVATA"
      puts "[ROUTING] ✅ Cambio modalità privata rilevato"
      self.core_cambio_modalita(bot, context)
    when "/miei", "📋 I MIEI ARTICOLI"
      puts "[ROUTING] ✅ Richiesta storico rilevata"
      self.handle_myitems(bot, context, false)
    when "/cleanup"
      puts "[ROUTING] ✅ Comando cleanup rilevato"
      self.core_cleanup(bot, context)
    else
      puts "[ROUTING] 🔍 Nessun comando pattern trovato. Controllo pending actions..."
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
    # 1. Recuperiamo gli ID corretti dal contesto (già popolati dal route)
    g_db_id = context.config["db_id"] || 0
    t_id = context.config["topic_id"] || 0
    
    puts "[CORE] 📋 Preparazione lista per G:#{g_db_id} T:#{t_id} (Page: #{page})"

    # 2. Gestione Header (Standardizzato e pulito)
    if g_db_id == 0
      header = "🏠 Lista Personale"
    else
      # Usiamo il DataManager per risolvere il nome "sperimentale" o "Generale"
      nome_t = DataManager.get_topic_name(g_db_id, t_id)
      g_nome = DB.get_first_value("SELECT nome FROM gruppi WHERE id = ?", [g_db_id]) || "Gruppo"
      header = "🎯 #{g_nome}: Lista #{nome_t}"
    end

    # 3. Recupero Articoli e Generazione UI
    items = DataManager.prendi_articoli_ordinati(g_db_id, t_id)
    ui = KeyboardGenerator.genera_lista(items, g_db_id, t_id, page, header)

    # 4. Invio Unificato (Gestendo il thread_id per i gruppi)
    begin
      params = {
        chat_id: context.chat_id,
        text: ui[:text],
        reply_markup: ui[:markup],
        parse_mode: "Markdown"
      }

      # Se siamo in un gruppo e il topic non è quello generale (0), serve il thread_id
      if !context.private_chat? && t_id > 0
        params[:message_thread_id] = t_id
        puts "[CORE] 🧵 Invio nel Topic ID: #{t_id}"
      end

      bot.api.send_message(params)
      puts "[CORE] ✅ Lista inviata con successo"
    rescue => e
      puts "❌ [CORE ERROR] Fallimento invio: #{e.message}"
    end
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
