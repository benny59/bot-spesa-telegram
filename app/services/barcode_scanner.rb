require 'net/http'
require 'json'
require 'open3'
require 'logger'
require 'fileutils'
require_relative '../handlers/to_pdf'

class BarcodeScanner
  @logger = Logger.new($stdout)

  def self.scan_image(path)
    return nil unless File.exist?(path)
    cmd = ["zbarimg", "--raw", path]
    out, err, status = Open3.capture3(*cmd)
    if status.success?
      barcode = out.lines.map(&:strip).find { |l| !l.empty? }
      barcode
    else
      @logger.warn("zbarimg failed: #{err.strip}")
      nil
    end
  rescue Errno::ENOENT
    @logger.error("zbarimg non trovato. Installa con: pkg install zbar")
    nil
  rescue => e
    @logger.error("BarcodeScanner error: #{e.class}: #{e.message}")
    nil
  end

  def initialize
    # Crea la directory per i JSON se non esiste
    @data_dir = File.expand_path(File.join(__dir__, '..', '..', 'data', 'products'))
    FileUtils.mkdir_p(@data_dir)
    puts "📁 Directory dati: #{@data_dir}"
  end

  def scan_barcode(image_path)
    barcode = self.class.scan_image(image_path)
    return nil unless barcode

    puts "🔍 Cercando prodotto con barcode: #{barcode}"
    fetch_product_info(barcode)
  end

  def get_product_info(barcode)
    fetch_product_info(barcode)
  end

  private

  def fetch_product_info(barcode)
    puts "📡 Interrogando OpenFoodFacts API per barcode: #{barcode}"
    
    begin
      url = "https://world.openfoodfacts.org/api/v0/product/#{barcode}.json"
      uri = URI(url)
      
      # Aggiungi timeout per sicurezza
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
      
      data = JSON.parse(response.body)
      
      # Salva la risposta completa come JSON
      save_product_json(barcode, data)
      
      if data['status'] == 1 && data['product']
    product = data['product']
    puts "✅ Prodotto trovato su OpenFoodFacts: #{product['product_name']}"
    
    {
      'product_name' => product['product_name'],
      'brands' => product['brands'],
      'categories' => product['categories'],
      'ingredients_text' => product['ingredients_text'],
      'nutriscore_grade' => product['nutriscore_grade'],
      'code' => barcode,
      'nutriments' => product['nutriments']  # ← AGGIUNGI QUESTA RIGA
    }
      else
        puts "❌ Prodotto NON trovato su OpenFoodFacts per barcode: #{barcode}"
        nil
      end
      
    rescue => e
      puts "❌ Errore durante la chiamata a OpenFoodFacts: #{e.message}"
      nil
    end
  end
  
  

  def save_product_json(barcode, data)
    json_file = File.join(@data_dir, "#{barcode}.json")
    
    begin
      File.open(json_file, 'w') do |f|
        f.write(JSON.pretty_generate(data))
      end
      puts "💾 Dati salvati in: #{json_file}"
    rescue => e
      puts "❌ Errore nel salvataggio JSON: #{e.message}"
    end
  end
end
