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
    # Controlla se il messaggio ha testo
    if message.text.nil?
      puts "Messaggio senza testo ricevuto: #{message.class}"
      return
    end

    case message.text
    when /\/start/
      send_welcome_message(message.chat.id)
    when /\/scan/
      send_scan_instructions(message.chat.id)
    when /\/nutrients/, /\/nutrition_stats/
      send_nutrition_stats(message)
    else
      process_product_query(message)
    end
  end

  private

  def send_welcome_message(chat_id)
    @bot.api.send_message(
      chat_id: chat_id, 
      text: "👋 Benvenuto nel bot Spesa! Usa /scan per scansionare un codice a barre."
    )
  end

  def send_scan_instructions(chat_id)
    @bot.api.send_message(
      chat_id: chat_id,
      text: "📷 Invia una foto del codice a barre del prodotto."
    )
  end

  def send_nutrition_stats(message)
    # Implementazione semplificata delle statistiche nutrizionali
    @bot.api.send_message(
      chat_id: message.chat.id,
      text: "📊 Funzione statistiche nutrizionali non ancora implementata.\nUsa /scan per scansionare prodotti."
    )
  end

  def process_product_query(message)
    query = message.text.strip
    
    # Se è un numero (potenziale barcode), cerca per barcode
    if query.match?(/^\d+$/)
      product = Product.find_latest_by_barcode(query)
      if product
        @bot.api.send_message(
          chat_id: message.chat.id, 
          text: "📦 Prodotto trovato nel database:\nBarcode: #{query}\nCaratteristiche: #{product[:characteristics]}"
        )
      else
        # Cerca su OpenFoodFacts
        product_info = @barcode_scanner.get_product_info(query)
        if product_info
          @bot.api.send_message(
            chat_id: message.chat.id,
            text: "🔍 Prodotto trovato su OpenFoodFacts:\n#{product_info['product_name'] || 'Nome non disponibile'}"
          )
        else
          @bot.api.send_message(
            chat_id: message.chat.id,
            text: "❌ Nessun prodotto trovato per il barcode: #{query}"
          )
        end
      end
    else
      # Se è testo, cerca per nome su OpenFoodFacts
      product_info = @openfoodfacts_client.search_products(query)
      if product_info && !product_info.empty?
        product = product_info.first
        @bot.api.send_message(
          chat_id: message.chat.id,
          text: "🔍 Prodotto trovato:\n#{product['product_name']}\nBarcode: #{product['code']}"
        )
      else
        @bot.api.send_message(
          chat_id: message.chat.id,
          text: "❌ Nessun prodotto trovato per: #{query}\nProva a scansionare un codice a barre con /scan"
        )
      end
    end
  end
end
