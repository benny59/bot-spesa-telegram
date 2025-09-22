require 'telegram/bot'
require_relative '../services/barcode_scanner'
require_relative '../services/openfoodfacts_client'
require_relative '../models/product'

class PhotoHandler
  def initialize(bot)
    @bot = bot
    @barcode_scanner = BarcodeScanner.new
    @openfoodfacts_client = OpenFoodFactsClient.new
  end

  def handle_photo(message)
    photo = message.photo.last
    file = @bot.api.get_file(file_id: photo.file_id)
    file_path = file['result']['file_path']
    file_url = "https://api.telegram.org/file/bot#{ENV['TELEGRAM_BOT_TOKEN']}/#{file_path}"

    # Here you would implement the logic to download the photo and scan for a barcode
    barcode = @barcode_scanner.scan(file_url)

    if barcode
      product_info = @openfoodfacts_client.fetch_product(barcode)
      if product_info
        save_product(product_info)
        @bot.api.send_message(chat_id: message.chat.id, text: "Prodotto trovato: #{product_info['product_name']}")
      else
        @bot.api.send_message(chat_id: message.chat.id, text: "Prodotto non trovato.")
      end
    else
      @bot.api.send_message(chat_id: message.chat.id, text: "Nessun codice a barre trovato.")
    end
  end

  private

  def save_product(product_info)
    product = Product.new
    product.name = product_info['product_name']
    product.barcode = product_info['code']
    product.characteristics = product_info['characteristics'] # Assuming characteristics is a field in the product_info
    product.save
  end
end