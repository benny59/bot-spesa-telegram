require 'prawn'
require 'prawn/table'
require 'mini_magick'

module NutritionChart
  def self.generate_radar_pdf(data, filepath, product_name = "Product")
    # Pulisci i dati
    cleaned_data = {}
    data.each { |k, v| cleaned_data[k] = v.to_f }
    
    # Filtra dati validi (> 0)
    valid_data = cleaned_data.select { |_, v| v > 0 }
    return nil if valid_data.empty?
    
    # Crea il PDF
    pdf_path = filepath.sub('.png', '.pdf')
    
    Prawn::Document.generate(pdf_path, page_size: 'A4', margin: [40, 40, 40, 40]) do |pdf|
      pdf.font_families.update(
        "OpenSans" => {
          normal: "/system/fonts/Roboto-Regular.ttf",
          bold: "/system/fonts/Roboto-Regular.ttf",
          italic: "/system/fonts/Roboto-Regular.ttf"
        }
      )
      pdf.font "OpenSans"
      
      # Header con colore
      pdf.fill_color "2E86AB"
      pdf.fill_rectangle([0, pdf.bounds.top], pdf.bounds.right, 60)
      pdf.fill_color "FFFFFF"
      pdf.text "PROFILO NUTRIZIONALE", size: 20, style: :bold, align: :center
      pdf.text product_name, size: 16, align: :center
      pdf.fill_color "000000"
      
      pdf.move_down 30
      
      # Tabella dati con design moderno
      pdf.fill_color "F8F9FA"
      pdf.fill_rectangle([0, pdf.cursor], pdf.bounds.right, 30)
      pdf.fill_color "2E86AB"
      pdf.text "VALORI PER 100g", size: 14, style: :bold, align: :center
      pdf.fill_color "000000"
      
      pdf.move_down 10
      
      # Mappa nomi italiani con emoji
      names_map = {
        'Energy' => '⚡ Energia',
        'Fat' => '🥓 Grassi', 
        'Carbs' => '🍚 Carboidrati',
        'Sugars' => '🍭 Zuccheri',
        'Protein' => '💪 Proteine',
        'Salt' => '🧂 Sale',
        'Fiber' => '🌾 Fibre'
      }
      
      # Tabella con design
      table_data = [['NUTRIENTE', 'VALORE', 'UNITA\'']]
      valid_data.each do |key, value|
        unit = key == 'Energy' ? 'kcal' : 'g'
        table_data << [names_map[key] || key, "%.1f" % value, unit]
      end
      
      pdf.table(table_data, width: pdf.bounds.width, header: true, 
                cell_style: { padding: [8, 12], border_width: 0.5 }) do
        cells.style do |cell|
          cell.border_color = "E9ECEF"
          cell.background_color = "FFFFFF"
        end
        
        row(0).style do |cell|
          cell.background_color = "2E86AB"
          cell.text_color = "FFFFFF"
          cell.font_style = :bold
          cell.align = :center
        end
        
        # Alternanza colori righe
        rows(1..-1).each_with_index do |row, i|
          row.background_color = i.even? ? "F8F9FA" : "FFFFFF"
        end
      end
      
      pdf.move_down 30
      
      # Grafico a barre orizzontali colorato
      draw_colorful_bars(pdf, valid_data)
      
      # Footer
      pdf.move_down 20
      pdf.stroke_color "E9ECEF"
      pdf.stroke_horizontal_rule
      pdf.move_down 10
      pdf.font("OpenSans", style: :italic) do
        pdf.text "Dati forniti da Open Food Facts", size: 10, align: :center, color: "6C757D"
      end
    end
    
    # Converti PDF in PNG
    convert_pdf_to_png(pdf_path, filepath)
    
    # Pulisci file PDF temporaneo
    File.delete(pdf_path) if File.exist?(pdf_path)
    
    filepath
  rescue => e
    puts "❌ Errore generazione PDF: #{e.message}"
    nil
  end

  private

  def self.draw_colorful_bars(pdf, data)
    return if data.empty?
    
    pdf.fill_color "2E86AB"
    pdf.text "CONFRONTO VISUALE", size: 14, style: :bold
    pdf.fill_color "000000"
    
    max_value = data.values.max
    start_y = pdf.cursor - 10
    bar_height = 20
    spacing = 25
    
    # Colori per le barre
    colors = ["FF6B6B", "4ECDC4", "45B7D1", "96CEB4", "FECA57", "FF9FF3", "54A0FF"]
    
    data.each_with_index do |(key, value), i|
      y = start_y - i * spacing
      bar_width = (value / max_value * 300).to_i
      color = colors[i % colors.length]
      
      # Barra colorata
      pdf.fill_color color
      pdf.fill_rectangle([50, y], bar_width, bar_height)
      
      # Bordo barra
      pdf.stroke_color "E9ECEF"
      pdf.stroke_rectangle([50, y], bar_width, bar_height)
      
      # Label nutriente
      pdf.fill_color "2D3436"
      label = case key
              when 'Energy' then 'Energia'
              when 'Fat' then 'Grassi'
              when 'Carbs' then 'Carboidrati'
              when 'Sugars' then 'Zuccheri'
              when 'Protein' then 'Proteine'
              when 'Salt' then 'Sale'
              when 'Fiber' then 'Fibre'
              else key
              end
      
      pdf.text_box label, at: [10, y + 15], width: 35, size: 9, align: :right
      
      # Valore numerico
      pdf.text_box "%.1f" % value, at: [bar_width + 60, y + 15], width: 40, size: 9, align: :left
      
      # Unità
      unit = key == 'Energy' ? 'kcal' : 'g'
      pdf.text_box unit, at: [bar_width + 105, y + 15], width: 20, size: 9, align: :left, color: "6C757D"
    end
    
    pdf.fill_color "000000"
  end

  def self.convert_pdf_to_png(pdf_path, png_path)
    return false unless File.exist?(pdf_path)
    
    # Converti con qualità migliore
    image = MiniMagick::Image.open(pdf_path)
    image.format("png")
    image.quality(100)
    image.density(300)  # Alta risoluzione
    image.resize("800x1000")  # Dimensioni ottimali per Telegram
    image.write(png_path)
    true
  rescue => e
    puts "❌ Errore conversione PDF→PNG: #{e.message}"
    false
  end
end
