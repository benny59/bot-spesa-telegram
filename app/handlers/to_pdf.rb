require 'prawn'
require 'json'

class ReportGenerator
  def self.generate_pdf(product_json, output_path = "report.pdf")
    product = product_json.is_a?(String) ? JSON.parse(product_json) : product_json

    Prawn::Document.generate(output_path) do |pdf|
      pdf.text "Report Prodotto", size: 20, style: :bold, align: :center
      pdf.move_down 20

      # Info generali
      pdf.text "📝 Informazioni generali", size: 16, style: :bold
      pdf.move_down 5
      pdf.text "Nome: #{product.dig('product_name') || 'N/D'}"
      pdf.text "Marca: #{product.dig('brands') || 'N/D'}"
      pdf.text "Quantità: #{product.dig('quantity') || 'N/D'}"
      pdf.text "Categoria: #{product.dig('categories_tags')&.join(', ') || 'N/D'}"
      pdf.move_down 15

      # Ingredienti
      pdf.text "🍇 Ingredienti", size: 16, style: :bold
      pdf.move_down 5
      pdf.text product.dig('ingredients_text') || 'N/D'
      pdf.move_down 15

      # Valori nutrizionali
      nutr = product.dig('nutriments') || {}
      pdf.text "⚡ Valori nutrizionali (per 100g)", size: 16, style: :bold
      pdf.move_down 5
      data = [
        ["Energia", "#{nutr['energy-kcal_100g'] || nutr['energy_100g']} kcal"],
        ["Grassi", "#{nutr['fat_100g']} g"],
        [" - Saturi", "#{nutr['saturated-fat_100g']} g"],
        ["Carboidrati", "#{nutr['carbohydrates_100g']} g"],
        [" - Zuccheri", "#{nutr['sugars_100g']} g"],
        ["Proteine", "#{nutr['proteins_100g']} g"],
        ["Fibre", "#{nutr['fiber_100g']} g"],
        ["Sale", "#{nutr['salt_100g']} g"]
      ].compact
      pdf.table(data, header: false, cell_style: { borders: [] })
      pdf.move_down 15

      # Valutazioni nutrizionali
      pdf.text "🥗 Valutazioni nutrizionali", size: 16, style: :bold
      pdf.move_down 5
      pdf.text "Nutri-Score: #{product.dig('nutriscore_grade')&.upcase || 'N/D'}"
      pdf.text "NOVA Group: #{product.dig('nova_group') || 'N/D'}"
      pdf.text "Ecoscore: #{product.dig('ecoscore_grade') || 'N/D'}"
    end

    puts "✅ Report PDF creato in #{output_path}"
  end
end
