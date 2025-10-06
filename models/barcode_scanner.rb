# models/barcode_scanner.rb
require "open3"
require "logger"

class BarcodeScanner
  @logger = Logger.new($stdout)

  def self.scan_image(path)
    return nil unless File.exist?(path)

    # Usa zbarimg SENZA --raw per avere formato e codice
    cmd = ["zbarimg", path]
    out, err, status = Open3.capture3(*cmd)

    puts "🔍 zbar output completo: '#{out}'"

    if status.success?
      # Pulisci l'output
      cleaned_output = out.strip
      puts "🔍 Output pulito: '#{cleaned_output}'"

      # Cerca pattern "FORMATO:CODICE" - usa split che è più robusto
      if cleaned_output.include?(":")
        parts = cleaned_output.split(":", 2)  # Split solo sulla prima occorrenza
        format = parts[0].downcase.gsub("-", "")  # "EAN-13" -> "ean13"
        value = parts[1].strip  # Rimuovi eventuali newline/spazi
        puts "✅ Formato rilevato: #{format}, Codice: #{value}"
        return { data: value, format: format }
      else
        puts "❌ Nessun barcode nel formato atteso"
        nil
      end
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
end
