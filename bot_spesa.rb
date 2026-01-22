# bot_spesa.rb (Versione Refactored v2 - Robust & Secure)

require "telegram/bot"
require "json"
require_relative "db"
require_relative "models/context"
require_relative "handlers/message_handler"
require_relative "handlers/callback_handler"

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
  puts "🤖 [BOT] In ascolto..."

  bot.listen do |update|
    begin
      case update
      when Telegram::Bot::Types::Message
        next if update.text.nil? && update.photo.empty?
        context = Context.from_message(update)
        MessageHandler.route(bot, update, context)
      when Telegram::Bot::Types::CallbackQuery
        # 🟢 QUESTO È IL PEZZO MANCANTE
        context = Context.from_callback(update)
        CallbackHandler.route(bot, update, context)
      end
    rescue => e
      puts "❌ [RUNTIME ERROR] #{e.class}: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end
  end
end
