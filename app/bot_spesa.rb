#!/usr/bin/env ruby
# bot_spesa.rb

require 'telegram/bot'
require_relative 'services/openfoodfacts_client'
require_relative 'services/barcode_scanner'
require_relative 'services/pdf_exporter'
require_relative 'handlers/message_handler'
require_relative 'handlers/photo_handler'
require_relative 'models/product'
require_relative 'models/config'

TOKEN = Config.find_by_key('token').value

Telegram::Bot::Client.run(TOKEN) do |bot|
  puts "Bot is running..."

  bot.listen do |message|
    case message
    when Telegram::Bot::Types::Message
      MessageHandler.handle(bot, message)
    when Telegram::Bot::Types::Photo
      PhotoHandler.handle(bot, message)
    end
  end
end