# bot_spesa.rb (Versione Refactored v2 - Robust & Secure)

# Nota: evitato require "resolv-replace" su Termux/Android
# perché il resolver Ruby dual-stack può bloccare le connessioni a api.telegram.org
# su IPv6 non instradato e causare timeout TCP/"execution expired".
require "telegram/bot"
require "json"
require_relative "db"
require_relative "models/context"
require_relative "handlers/message_handler"
require_relative "handlers/callback_handler"
require_relative "utils/command_setter"

# In bot_spesa.rb
PID_FILE = File.join(__dir__, "bot_spesa.pid")
File.write(PID_FILE, Process.pid)

# Opzionale: cancella il file quando il bot si spegne pulitamente
at_exit { File.delete(PID_FILE) if File.exist?(PID_FILE) }

# 1. GESTIONE TOKEN SICURA (Priorità: ENV > DB)
TOKEN = ENV["TELEGRAM_BOT_TOKEN"] || begin
  env = DB.get_first_value("SELECT value FROM config WHERE key = 'environment'") || "development"
  token_key = env == "development" ? "token_dev" : "token"
  DB.get_first_value("SELECT value FROM config WHERE key = ?", token_key)
end

if TOKEN.nil? || TOKEN.empty?
  puts "❌ [FATAL] Token non trovato. Imposta TELEGRAM_BOT_TOKEN o verifica il DB."
  exit 1
end

# 2. GESTIONE SEGNALI (Graceful Shutdown)
Signal.trap("INT") { puts "\n🛑 Spegnimento (SIGINT)..."; exit }
Signal.trap("TERM") { puts "\n🛑 Spegnimento (SIGTERM)..."; exit }

# 3. AVVIO MONITOR DB
begin
  DataManager.setup_database
  puts "🚀 [START] Bot attivo (Ambiente: #{ENV["BOT_ENV"] || "detecting..."})"
rescue => e
  puts "❌ [ERROR] Fallimento setup DB: #{e.message}"
  exit 1
end

# 4. LOOP PRINCIPALE
Telegram::Bot::Client.run(TOKEN) do |bot|
  CommandSetter.aggiorna_comandi(bot)
  puts "🤖 [BOT] In ascolto..."

  bot.listen do |update|
    # Debug per vedere TUTTO quello che arriva da Telegram
    #puts "🔍 [RAW_RECEIVE] Tipo: #{update.class} | JSON: #{update.to_json}"
    begin
      case update
      when Telegram::Bot::Types::Message
        # AGGIORNATO: Permettiamo il passaggio anche se è un cambio titolo gruppo
        is_service_msg = update.forum_topic_created || update.forum_topic_edited || update.new_chat_title

        next if update.text.nil? && update.photo.nil? && !is_service_msg

        context = Context.from_message(update)
        MessageHandler.route(bot, update, context)
      when Telegram::Bot::Types::CallbackQuery
        context = Context.from_callback(update)
        CallbackHandler.route(bot, update, context)
      else
        # 🔴 IL "CATTURA TUTTO": Qui finiscono le rinomine, i nuovi membri, etc.
        puts "⚠️ [UPDATE_SCONOSCIUTO] Tipo: #{update.class}"
        puts "Contenuto: #{update.to_json}"
      end
    rescue => e
      puts "❌ [RUNTIME ERROR] #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end
end
