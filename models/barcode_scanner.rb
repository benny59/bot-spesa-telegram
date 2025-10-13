# models/barcode_scanner.rb
require "open3"
require "logger"

class BarcodeScanner
  @logger = Logger.new($stdout)

  def self.scan_image(path)
    return nil unless File.exist?(path)

    python_code = <<~PYTHON
      import zxing
      reader = zxing.BarCodeReader()
      result = reader.decode("#{path}", try_harder=True)
      if result and result.parsed:
          print(f"{result.parsed}|{result.format}")
      else:
          print("")
    PYTHON

    # Usa directory corrente invece di Dir.tmpdir
    temp_file = "temp_barcode_decode.py"
    File.write(temp_file, python_code)
    
    # Esegui Python
    out, err, status = Open3.capture3("python3", temp_file)
    
    # Pulizia
    File.delete(temp_file) if File.exist?(temp_file)
    
    if status.success? && !out.strip.empty?
      if out.include?("|")
        code, format = out.strip.split("|", 2)
        { data: code, format: format.downcase }
      else
        { data: out.strip, format: "unknown" }
      end
    else
      @logger.warn("ZXing failed for #{path}: #{err.strip}") unless err.empty?
      nil
    end
    
  rescue => e
    @logger.error("BarcodeScanner error: #{e.class}: #{e.message}")
    nil
  end

  # Metodo di fallback con zbarimg
  def self.scan_image_fallback(path)
    return nil unless File.exist?(path)

    cmd = ["zbarimg", "--quiet", path]
    out, err, status = Open3.capture3(*cmd)

    if status.success?
      cleaned_output = out.strip
      if cleaned_output.include?(":")
        parts = cleaned_output.split(":", 2)
        format = parts[0].downcase.gsub("-", "")
        value = parts[1].strip
        return { data: value, format: format }
      end
    end
    nil
  rescue => e
    @logger.error("Fallback scanner error: #{e.message}")
    nil
  end
end
