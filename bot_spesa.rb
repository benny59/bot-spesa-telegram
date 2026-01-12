# bot_spesa.rb
require "telegram/bot"
require_relative "db"
require_relative "handlers/message_handler"
require_relative "utils/command_setter"

require_relative "handlers/callback_handler"
require_relative "models/context"

# =============================
# BOOTSTRAP
# =============================
env = DB.get_first_value("SELECT value FROM config WHERE key = 'environment'") || "production"
token_key = env == "development" ? "token_dev" : "token"
token = DB.get_first_value("SELECT value FROM config WHERE key = ?", token_key)

# Se il token non è nel DB, lo chiediamo all'utente
if token.nil? || token.strip.empty?
  puts "⚠️  [CONFIG] Token Telegram non trovato nel database (#{token_key})"
  print "👉 Inserisci il token per l'ambiente #{env}: "
  token = gets.chomp.strip

  if token.empty?
    puts "❌ Nessun token inserito. Arresto del bot."
    exit
  end

  # Salviamo il token nel DB per i prossimi riavvii
  DB.execute("INSERT OR REPLACE INTO config (key, value) VALUES (?, ?)", [token_key, token])
  puts "✅ Token salvato correttamente nel database."
end

puts "🤖 Avvio bot in ambiente: #{env}"

Telegram::Bot::Client.run(token) do |bot|
  puts "✅ Bot avviato correttamente"
CommandSetter.aggiorna_comandi(bot)

  bot.listen do |update|
    begin
      case update
      when Telegram::Bot::Types::Message
        context = Context.from_message(update)
        MessageHandler.route(bot, update, context)
      when Telegram::Bot::Types::CallbackQuery
        context = Context.from_callback(update)
        CallbackHandler.route(bot, update, context)
      end
    rescue => e
      puts "❌ Errore runtime: #{e.class} - #{e.message}"
      puts e.backtrace.first(5)
    end
  end
end
