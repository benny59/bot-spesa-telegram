# helpers/batch_scanner.rb
class BatchScanner
  def self.scan_directory(directory_path = ".")
    results = {}
    
    # Cerca tutte le immagini
    image_extensions = ["*.jpg", "*.jpeg", "*.png", "*.bmp", "*.gif"]
    
    image_extensions.each do |ext|
      Dir[File.join(directory_path, ext)].each do |image_file|
        puts "🔍 Scansionando: #{File.basename(image_file)}"
        
        # Prova prima ZXing, poi fallback
        result = BarcodeScanner.scan_image(image_file)
        
        if result
          results[File.basename(image_file)] = result
          puts "✅ Trovato: #{result[:data]} (#{result[:format]})"
        else
          results[File.basename(image_file)] = { error: "Nessun codice trovato" }
          puts "❌ Nessun codice"
        end
        puts "---"
      end
    end
    
    results
  end
  
  def self.export_to_csv(results, output_file = "barcode_results.csv")
    require "csv"
    
    CSV.open(output_file, "w") do |csv|
      csv << ["File", "Codice", "Formato", "Stato"]
      
      results.each do |filename, data|
        if data[:data]
          csv << [filename, data[:data], data[:format], "SUCCESS"]
        else
          csv << [filename, "", "", data[:error] || "UNKNOWN_ERROR"]
        end
      end
    end
    
    puts "📊 Risultati esportati in: #{output_file}"
  end
end
