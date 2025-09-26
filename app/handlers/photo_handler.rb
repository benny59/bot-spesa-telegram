require 'telegram/bot'
require 'open-uri'
require 'securerandom'
require_relative '../services/barcode_scanner'
require_relative '../models/product'
require_relative '../services/nutrition_chart'


class PhotoHandler
  def initialize(bot, token)
    @bot = bot
    @token = token
    @barcode_scanner = BarcodeScanner.new
  end

  def handle_photo(message)
    tmp_file = nil
    
    begin
      # Ottieni la foto più grande (ultima nell'array)
      photo = message.photo.last
      file_response = @bot.api.get_file(file_id: photo.file_id)
      
      puts "File response class: #{file_response.class}"
      
      # Gestione flessibile del file path
      file_path = if file_response.respond_to?(:file_path)
                    file_response.file_path
                  elsif file_response.is_a?(Hash) && file_response['result']
                    file_response['result']['file_path']
                  else
                    file_response.file_path
                  end
      
      file_url = "https://api.telegram.org/file/bot#{@token}/#{file_path}"

      # Crea il percorso tmp per Termux
      tmp_dir = "/data/data/com.termux/files/usr/tmp"
      Dir.mkdir(tmp_dir) unless Dir.exist?(tmp_dir)
      tmp_file = File.join(tmp_dir, "photo_#{SecureRandom.hex}.jpg")
      
      # Scarica l'immagine
      URI.open(file_url) do |image|
        File.open(tmp_file, 'wb') { |f| f.write(image.read) }
      end

      puts "File scaricato: #{tmp_file}"
      puts "Dimensione file: #{File.size(tmp_file)} bytes"

      # Scansiona il barcode
      barcode = BarcodeScanner.scan_image(tmp_file)
      puts "Barcode trovato: #{barcode}"
      
      if barcode
        # Cerca il prodotto
        product_info = @barcode_scanner.get_product_info(barcode)
        
        if product_info
          # Salva il prodotto
          save_product(product_info, barcode, message.chat.id)
          send_nutrition_chart(product_info, message.chat.id)
          @bot.api.send_message(
            chat_id: message.chat.id,
            text: "✅ Prodotto trovato: #{product_info['product_name'] || 'Nome non disponibile'}\nCodice: #{barcode}"
          )
        else
          # Salva comunque il barcode anche se prodotto non trovato
          save_product({
            'product_name' => "Prodotto non identificato",
            'brands' => '',
            'categories' => ''
          }, barcode, message.chat.id)
          
          @bot.api.send_message(
            chat_id: message.chat.id,
            text: "📦 Barcode scansionato: #{barcode}\n⚠️ Prodotto non trovato su OpenFoodFacts, ma salvato nel database."
          )
        end
      else
        @bot.api.send_message(
          chat_id: message.chat.id,
          text: "⚠️ Nessun codice a barre trovato nell'immagine. Assicurati che la foto sia nitida."
        )
      end
      
    rescue => e
      puts "❌ Errore durante l'elaborazione della foto: #{e.message}"
      puts e.backtrace
      
      @bot.api.send_message(
        chat_id: message.chat.id,
        text: "❌ Errore durante l'elaborazione della foto. Riprova."
      )
    ensure
      # Pulisci SEMPRE il file temporaneo
      if tmp_file && File.exist?(tmp_file)
        File.delete(tmp_file)
        puts "File temporaneo pulito: #{tmp_file}"
      end
    end
  end

  private
  
def send_nutrition_chart(product_info, chat_id)
  return unless product_info['nutriments']
  
  nutriments = product_info['nutriments']
  
  # Pulisci i dati
  nutrition_data = {
    'Energy' => (nutriments['energy-kcal'] || 0).to_f,
    'Fat' => (nutriments['fat'] || 0).to_f,
    'Carbs' => (nutriments['carbohydrates'] || 0).to_f,
    'Sugars' => (nutriments['sugars'] || 0).to_f,
    'Protein' => (nutriments['proteins'] || 0).to_f,
    'Salt' => (nutriments['salt'] || 0).to_f,
    'Fiber' => (nutriments['fiber'] || 0).to_f
  }
  
  filtered_data = nutrition_data.select { |_, v| v > 0 }
  
  if filtered_data.any?
    tmp_dir = "/data/data/com.termux/files/usr/tmp"
    chart_file = File.join(tmp_dir, "nutrition_chart_#{SecureRandom.hex}.png")
    
    product_name = product_info['product_name'] || "Prodotto"
    
    if NutritionChart.generate_radar_pdf(filtered_data, chart_file, product_name)
      @bot.api.send_photo(
        chat_id: chat_id,
        photo: Faraday::UploadIO.new(chart_file, 'image/png'),
        caption: "📊 🍎 **Profilo nutrizionale completo**\n#{product_name}"
      )
      
      File.delete(chart_file) if File.exist?(chart_file)
    else
      send_nutrition_text(product_info, chat_id)
    end
  else
    @bot.api.send_message(
      chat_id: chat_id,
      text: "⚠️ Nessun dato nutrizionale disponibile per questo prodotto"
    )
  end
rescue => e
  puts "❌ Errore nell'invio del grafico: #{e.message}"
  send_nutrition_text(product_info, chat_id)
end

def send_nutrition_text(product_info, chat_id)
  return unless product_info['nutriments']
  
  nutriments = product_info['nutriments']
  product_name = product_info['product_name'] || "Prodotto"
  
  text = "📊 <b>PROFILO NUTRIZIONALE - #{product_name}</b>\n\n"
  text += "<i>Valori per 100g:</i>\n\n"
  
  nutrition_data = {
    '🔋 Energia' => "#{nutriments['energy-kcal']&.round(1) || 0} kcal",
    '🥓 Grassi' => "#{nutriments['fat']&.round(1) || 0} g",
    '🍚 Carboidrati' => "#{nutriments['carbohydrates']&.round(1) || 0} g",
    '🍭 Zuccheri' => "#{nutriments['sugars']&.round(1) || 0} g",
    '💪 Proteine' => "#{nutriments['proteins']&.round(1) || 0} g",
    '🧂 Sale' => "#{nutriments['salt']&.round(1) || 0} g",
    '🌾 Fibre' => "#{nutriments['fiber']&.round(1) || 0} g"
  }
  
  nutrition_data.each { |name, value| text += "• #{name}: <b>#{value}</b>\n" }
  
  @bot.api.send_message(
    chat_id: chat_id,
    text: text,
    parse_mode: 'HTML'
  )
end
end

  def save_product(product_info, barcode, chat_id)
    # Usa il metodo esistente della classe Product
    characteristics = {
      name: product_info['product_name'],
      brand: product_info['brands'],
      categories: product_info['categories'],
      ingredients: product_info['ingredients_text'],
      nutriscore: product_info['nutriscore_grade']
    }
    
    # USA IL METODO PRINCIPALE
    success = Product.save_for_item(
      item_id: chat_id,
      barcode: barcode,
      characteristics: characteristics
    )
    
    if success
      puts "✅ Prodotto salvato nel database"
    else
      puts "❌ Errore nel salvataggio database"
    end
  end

