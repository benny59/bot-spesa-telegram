#!/usr/bin/env ruby
# bot_spesa.rb
require 'telegram/bot'
require_relative 'db'
require_relative 'models/lista'
require_relative 'models/group_manager'
require_relative 'handlers/callback_handler'
require_relative 'handlers/message_handler'
#require_relative 'handlers/command_handler'
require_relative 'utils/keyboard_generator'

# recupera token dal DB (config key/value)
token = DB.get_first_value("SELECT value FROM config WHERE key = 'token'")

if token.nil? || token.to_s.strip.empty?
  puts "⚙️ Inserisci il token nella tabella config: ruby config_tool.rb token 123456:ABC..."
  exit 1
end

Telegram::Bot::Client.run(token) do |bot|
  puts "🤖 Bot avviato!"
  bot_username = bot.api.get_me.username rescue nil
  puts "🔗 Username bot: @#{bot_username}" if bot_username

  # comandi ufficiali / menu
  begin
    bot.api.set_my_commands(commands: [
      {command: 'start', description: 'Avvia il bot'},
      {command: 'newgroup', description: 'Crea gruppo virtuale'},
      {command: 'lista', description: 'Mostra la lista della spesa'},
      {command: 'ss', description: 'Screenshot lista della spesa'},
      {command: 'help', description: 'Mostra i comandi disponibili'}
    ])
  rescue => e
    puts "⚠️ set_my_commands fallito: #{e.message}"
  end

  Signal.trap("INT") { puts "\n🛑 Arresto del bot..."; exit }

  bot.listen do |msg|
    begin
      puts "=" * 40
      puts "📨 NUOVO: #{msg.class}"

      case msg
      when Telegram::Bot::Types::CallbackQuery
        CallbackHandler.handle(bot, msg)
      when Telegram::Bot::Types::Message
        MessageHandler.handle(bot, msg, bot_username)
      end
    rescue => e
      puts "❌ Errore: #{e.message}"
      puts e.backtrace
    end
  end
end
