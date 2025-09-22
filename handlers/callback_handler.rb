require_relative '../models/lista'
require_relative '../app/models/product'
require_relative '../app/services/openfoodfacts_client'
require_relative '../app/services/job_queue'

def handle_callback(callback_query, bot)
  data = callback_query.data.to_s
  if data.start_with?('confirm_take:')
    parts = data.split(':', 4) # e.g. confirm_take:yes:ITEMID:BARCODE
    _marker, decision, item_id_s, barcode = parts
    item_id = item_id_s.to_i

    if decision == 'no'
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: 'Operazione annullata.')
      return
    end

    success = false
    begin
      if Lista.respond_to?(:toggle_comprato)
        arity = Lista.method(:toggle_comprato).arity
        if arity == 1
          Lista.toggle_comprato(item_id)
        elsif arity == 2
          initials = callback_query.from.first_name.to_s[0,2].upcase rescue ''
          Lista.toggle_comprato(item_id, initials)
        end
        success = true
      elsif Lista.respond_to?(:segna_comprato)
        Lista.segna_comprato(item_id)
        success = true
      elsif Lista.respond_to?(:rimuovi)
        Lista.rimuovi(item_id)
        success = true
      end
    rescue => e
      warn "confirm_take error toggling item: #{e.class}: #{e.message}"
    end

    # Enqueue the potentially slow OpenFoodFacts lookup and product save so the callback response is fast.
    if barcode && !barcode.empty?
      JobQueue.enqueue do
        begin
          off_res = OpenFoodFactsClient.fetch_product_info(barcode)
          Product.save_for_item(item_id: item_id, barcode: barcode, characteristics: (off_res[:data] || {})) if off_res && off_res[:ok]
        rescue => e
          warn "Deferred OFF save error: #{e.class}: #{e.message}"
        end
      end
    end

    if success
      bot.api.edit_message_text(chat_id: callback_query.message.chat.id,
                                message_id: callback_query.message.message_id,
                                text: "✅ Elemento segnato come comprato.")
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: 'Elemento aggiornato.')
    else
      bot.api.answer_callback_query(callback_query_id: callback_query.id, text: 'Impossibile aggiornare l\'elemento. Controlla i log.')
    end
    return
  end

  # ...existing callback handling...
end