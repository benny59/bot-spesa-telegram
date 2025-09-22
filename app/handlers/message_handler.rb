require 'telegram/bot'
require_relative '../services/openfoodfacts_client'
require_relative '../services/barcode_scanner'
require_relative '../models/product'

class MessageHandler
  def initialize(bot)
    @bot = bot
    @openfoodfacts_client = OpenFoodFactsClient.new
    @barcode_scanner = BarcodeScanner.new
  end

  def handle_message(message)
    case message.text
    when /\/start/
      send_welcome_message(message.chat.id)
    when /\/scan/
      send_scan_instructions(message.chat.id)
    else
      process_product_query(message)
    end
  end

  private

  def send_welcome_message(chat_id)
    @bot.api.send_message(chat_id: chat_id, text: "👋 Benvenuto nel bot Spesa! Usa /scan per scansionare un codice a barre.")
  end

  def send_scan_instructions(chat_id)
    @bot.api.send_message(chat_id: chat_id, text: "📷 Invia una foto del codice a barre del prodotto.")
  end

  def process_product_query(message)
    product = Product.find_by_name(message.text)
    if product
      @bot.api.send_message(chat_id: message.chat.id, text: "Prodotto trovato: #{product.name} - #{product.characteristics}")
    else
      @bot.api.send_message(chat_id: message.chat.id, text: "❌ Prodotto non trovato. Prova a scansionare un codice a barre.")
    end
  end
end