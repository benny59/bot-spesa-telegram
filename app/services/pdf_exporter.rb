require 'prawn'
require_relative '../models/product'

class PDFExporter
  # items: array of hashes with at least: { id: Integer, text: String, qty: String/Integer, bought: Boolean }
  # out_path: local path to write the PDF
  def self.export_list(items, out_path)
    Prawn::Document.generate(out_path, page_size: 'A4') do |pdf|
      pdf.font_size 12
      pdf.text "Lista della spesa", size: 18, style: :bold, align: :center
      pdf.move_down 12

      items.each_with_index do |item, idx|
        line = "#{idx + 1}. #{item[:text].to_s}"
        line += " (#{item[:qty]})" if item[:qty]
        line += item[:bought] ? " ✅" : ""
        pdf.text line, leading: 2

        # attach product characteristics if available
        product = Product.find_by_item(item[:id]) rescue nil
        if product && product[:characteristics].is_a?(Hash)
          attrs = product[:characteristics]
          # prefer product name/brand/quantity from OFF, fall back to attributes stored
          name = attrs['name'] || attrs[:name] || attrs['product_name']
          brand = attrs['brand'] || attrs[:brand] || attrs['brands']
          qty = attrs['quantity'] || attrs[:quantity]
          nutriments = attrs['nutriments'] || attrs[:nutriments] || {}

          pdf.font_size 9
          pdf.indent(12) do
            pdf.text "— Prodotto:", style: :bold
            pdf.text "Nome: #{name}" if name && name != 'N/A'
            pdf.text "Marca: #{brand}" if brand && brand != 'N/A'
            pdf.text "Quantità: #{qty}" if qty && qty != 'N/A'
            unless nutriments.empty?
              # pick a few common nutriments if present
              selected = {}
              %w[energy kcal proteins fat carbohydrates salt sugars].each do |k|
                selected[k] = nutriments[k] if nutriments[k]
              end
              unless selected.empty?
                pdf.move_down 2
                pdf.text "Nutrienti (parziale):"
                selected.each do |k, v|
                  pdf.text "  - #{k}: #{v}"
                end
              end
            end
          end
          pdf.move_down 6
          pdf.font_size 12
        else
          pdf.move_down 4
        end
      end

      pdf.move_down 12
      pdf.text "Generato da bot-spesa-telegram", size: 8, align: :right
    end
  end
end