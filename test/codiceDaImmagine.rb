# codiceDaImmagine.rb
require_relative "../models/barcode_scanner"
require_relative "./batch_scanner"

# Verifica semplice delle dipendenze
def check_dependencies
  # Verifica se Python e zxing sono installati
  python_check = `python3 -c "import zxing; print('OK')" 2>&1`
  unless python_check.include?("OK")
    puts "⚠️  ZXing non trovato. Installazione automatica..."
    system("pip install zxing")
  end
end

def main
  check_dependencies

  if ARGV.empty?
    # Modalità batch - scansiona tutto
    puts "🎯 Scansione batch di tutte le immagini..."
    results = BatchScanner.scan_directory(".")

    # Esporta risultati
    BatchScanner.export_to_csv(results)

    # Riepilogo
    success_count = results.count { |_, data| data[:data] }
    puts "\n📈 Riepilogo: #{success_count}/#{results.size} codici trovati"
  else
    # Modalità singolo file
    ARGV.each do |file_path|
      if File.exist?(file_path)
        puts "🔍 Scansionando: #{file_path}"
        result = BarcodeScanner.scan_image(file_path)

        if result
          puts "✅ Codice: #{result[:data]}"
          puts "📊 Formato: #{result[:format]}"
        else
          puts "❌ Nessun codice trovato"
        end
      else
        puts "❌ File non trovato: #{file_path}"
      end
      puts "---"
    end
  end
end

main if __FILE__ == $0
