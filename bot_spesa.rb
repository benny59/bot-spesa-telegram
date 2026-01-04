# bot_spesa.rb
require "telegram/bot"
require_relative "db"
require_relative "handlers/message_handler"
require_relative "handlers/callback_handler"
require_relative "models/context"

# =============================
# BOOTSTRAP
# =============================
env = DB.get_first_value("SELECT value FROM config WHERE key = 'environment'") || "production"
token_key = env == "development" ? "token_dev" : "token"
token = DB.get_first_value("SELECT value FROM config WHERE key = ?", token_key)

abort("❌ Token Telegram non trovato in config (#{token_key})") unless token

puts "🤖 Avvio bot in ambiente: #{env}"

Telegram::Bot::Client.run(token) do |bot|
  puts "✅ Bot avviato correttamente"

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
