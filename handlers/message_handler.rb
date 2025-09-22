require_relative '../app/services/job_queue'
require_relative '../app/services/barcode_scanner'
require_relative '../app/services/openfoodfacts_client'
require_relative '../app/services/product_matcher'
require_relative '../app/models/product'
require_relative '../models/lista'

# Helper: scan a downloaded image, query OpenFoodFacts, try to match a list item and ask for confirmation.
# Call this after you download the Telegram photo to local_path.
def attach_product_and_prompt_async(bot, message, local_path, item_id = nil)
  JobQueue.enqueue do
    begin
      barcode = BarcodeScanner.scan_image(local_path)
      next unless barcode && !barcode.empty?

      res = OpenFoodFactsClient.fetch_product_info(barcode)
      unless res && res[:ok] && res[:data]
        begin
          bot.api.send_message(chat_id: message.chat.id,
                               text: "⚠️ Barcode trovata: #{barcode}, ma nessuna informazione disponibile.")
        rescue => _e
        end
        next
      end

      Product.save_for_item(item_id: item_id, barcode: barcode, characteristics: res[:data]) if item_id

      # get list items (try both signatures)
      items = []
      begin
        items = Lista.tutti(message.chat.id)
      rescue => _
        begin
          items = Lista.tutti
        rescue => _
          items = []
        end
      end

      match = ProductMatcher.match_against_items(res[:data], items, threshold: 0.45)
      if match
        item = match[:item]
        score = (match[:score] * 100).round(0)
        kb = {
          inline_keyboard: [
            [
              { text: "Segna '#{item[:text].to_s[0..50]}' come comprato (#{score}%)",
                callback_data: "confirm_take:yes:#{item[:id]}:#{barcode}" },
              { text: 'No', callback_data: "confirm_take:no:#{item[:id]}:#{barcode}" }
            ]
          ]
        }

        begin
          bot.api.send_message(chat_id: message.chat.id,
                               text: "Ho riconosciuto: *#{res[:data]['name'] || res[:data]['product_name'] || 'prodotto'}* che sembra corrispondere a '#{item[:text]}'. Vuoi segnarlo come comprato?",
                               parse_mode: 'Markdown',
                               reply_markup: kb)
        rescue => _e
        end
      else
        begin
          bot.api.send_message(chat_id: message.chat.id,
                               text: "Prodotto riconosciuto: *#{res[:data]['name'] || res[:data]['product_name']}* — nessuna corrispondenza trovata nella lista.",
                               parse_mode: 'Markdown')
        rescue => _e
        end
      end
    rescue => e
      warn "attach_product_and_prompt_async error: #{e.class}: #{e.message}"
    end
  end
end

# Example usage (where you handle downloaded photo and created item):
# attach_product_and_prompt_async(bot, message, local_path, item_id)

when '/nutrients', '/nutrition_stats'
  # collect nutrients for bought items in the current group
  group_id = current_group_id_from_update(update)
  db = DB.db

  sql = <<-SQL
    SELECT
      COALESCE(SUM(p.energy_kcal),0),
      COALESCE(SUM(p.fat_g),0),
      COALESCE(SUM(p.saturated_fat_g),0),
      COALESCE(SUM(p.carbohydrates_g),0),
      COALESCE(SUM(p.sugars_g),0),
      COALESCE(SUM(p.proteins_g),0),
      COALESCE(SUM(p.salt_g),0),
      COALESCE(SUM(p.fiber_g),0)
    FROM lista l
    JOIN products p ON (p.id = l.product_id)
    WHERE l.gruppo_id = ? AND l.comprato = 1
  SQL

  row = db.get_first_row(sql, group_id) || [0]*8
  nutrients = {
    'Energy (kcal)' => row[0].to_f,
    'Fat (g)' => row[1].to_f,
    'SatFat (g)' => row[2].to_f,
    'Carbs (g)' => row[3].to_f,
    'Sugars (g)' => row[4].to_f,
    'Proteins (g)' => row[5].to_f,
    'Salt (g)' => row[6].to_f,
    'Fiber (g)' => row[7].to_f
  }

  chart_path = File.join(Dir.tmpdir, "nutrients_#{group_id}_#{Time.now.to_i}.png")
  NutritionChart.generate_radar(nutrients, chart_path)

  # send the generated image back to the chat
  bot.api.send_photo(chat_id: chat_id, photo: Faraday::UploadIO.new(chart_path, 'image/png'))