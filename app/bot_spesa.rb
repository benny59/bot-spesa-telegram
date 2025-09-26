#!/usr/bin/env ruby
# bot_spesa.rb

require 'telegram/bot'
require 'sqlite3'
require_relative 'services/openfoodfacts_client'
require_relative 'services/barcode_scanner'
require_relative 'services/nutrition_chart'

require_relative 'handlers/to_pdf'
require_relative 'handlers/message_handler'
require_relative 'handlers/photo_handler'
require_relative 'models/product'
require_relative 'models/config'

# Connessione al database
DB = SQLite3::Database.new('../spesa.db')

# Leggi il token dal DB
TOKEN = Config.find(DB, 'token')

if TOKEN.nil? || TOKEN.strip.empty?
  puts "❌ Nessun token trovato nella tabella config."
  puts "💡 Esegui prima: ruby app/start_config.rb"
  abort "Token non configurato"
end

puts "🤖 Bot avviato con token: #{TOKEN[0..10]}..." # Log parziale per sicurezza

Telegram::Bot::Client.run(TOKEN) do |bot|
  puts "🤖 Bot avviato e in ascolto..."
  message_handler = MessageHandler.new(bot)
  photo_handler = PhotoHandler.new(bot, TOKEN)

  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      # Controlla se il messaggio contiene una foto
      if message.photo && !message.photo.empty?
        puts "📸 Foto ricevuta da: #{message.chat.id}"
        photo_handler.handle_photo(message)
      elsif message.text
        puts "💬 Messaggio testo: #{message.text[0..50]}..."
        message_handler.handle_message(message)
      else
        puts "❓ Messaggio non gestito: #{message.class}"
      end
    else
      puts "🔔 Tipo messaggio non gestito: #{message.class}"
    end
  rescue => e
    puts "💥 Errore nel loop principale: #{e.message}"
    puts e.backtrace
  end
end
