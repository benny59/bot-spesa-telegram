#!/usr/bin/env ruby
# frozen_string_literal: true

# ANTEPRIMA della pulizia del catalogo prodotti: elenca cosa toglierebbe il comando di cleanup, senza scrivere.
# La cancellazione vera avviene solo dal comando Telegram del creatore (con backup): stesso criterio, un solo punto
# (DataManager.prodotti_catalogo_scaduti).
#
#   ruby scripts/pulizia_catalogo.rb
#   SPESA_DB=copia.db ruby scripts/pulizia_catalogo.rb

require File.expand_path("../db", __dir__)

da_togliere = DataManager.prodotti_catalogo_scaduti
totale = DB.get_first_value("SELECT COUNT(*) FROM prodotti")
puts "\n===== ANTEPRIMA (nessuna scrittura) su #{DB_PATH} ====="
puts "Prodotti nel catalogo: #{totale}; da togliere (mai ripetuti da oltre #{DataManager::GIORNI_CATALOGO_INUTILIZZATO} giorni): #{da_togliere.size}"
da_togliere.each { |r| puts "  - #{r['gtin']} #{r['descrizione']} (usi #{r['utilizzi']}, ultimo uso #{r['ultimo_uso']})" }
puts "Righe di storico prodotti orfane: #{DB.get_first_value('SELECT COUNT(*) FROM storico_articolo_prodotti WHERE storico_articolo_id NOT IN (SELECT id FROM storico_articoli)')}"
