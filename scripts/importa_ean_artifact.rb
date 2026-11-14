#!/usr/bin/env ruby
# frozen_string_literal: true

# Importa in spesa.db i codici EAN raccolti dall'artifact "Basket Index".
#
#   SPESA_DB=/percorso/copia.db ruby scripts/importa_ean_artifact.rb export.json           # dry-run (default)
#   SPESA_DB=/percorso/copia.db ruby scripts/importa_ean_artifact.rb export.json --apply   # scrive
#   ... --apply --openfood   # in più scarica da Open Food Facts la scheda dei codici che ne sono privi
#                            # (una richiesta al secondo, esce solo il codice a barre)
#
# Input: il file "basket-index-AAAA-MM-GG.json" della Copia di sicurezza dell'artifact
# (documenti kind:"product" con ean, names, store, brand/product/size, nut).
#
# Regole prudenti (non sovrascrive mai ciò che c'è):
#  - GTIN invalido (cifra di controllo) -> scartato e segnalato.
#  - prodotto nuovo -> inserito con fonte "artifact"; descrizione = etichetta (marca prodotto formato)
#    se nota, altrimenti la prima descrizione da scontrino (origine "scontrino", la più bassa).
#  - priorità del nome: preferiti > storico > scontrino. Se il GTIN è tra i preferiti (o nello storico) il nome
#    diventa quello; il nome sostituito resta come alias. Non scende mai di priorità.
#  - prodotto già presente -> la scheda Open Food Facts resta; se manca del tutto la scheda
#    e l'artifact ha i valori d'etichetta, si salva una scheda minima (verrà sostituita da OFF al primo controllo).
#  - le descrizioni da scontrino (per negozio) diventano alias compatti in `prodotto_alias`.
#  - stesso EAN con etichette diverse (kcal che differiscono >10%) -> segnalato, i valori non vengono importati.

require "json"

apply = ARGV.delete("--apply")
openfood = ARGV.delete("--openfood")
abort "--openfood richiede --apply" if openfood && !apply
file = ARGV.first
abort "Uso: SPESA_DB=copia.db ruby #{$PROGRAM_NAME} export.json [--apply]" unless file && File.file?(file)

require File.expand_path("../db", __dir__)

export = JSON.parse(File.read(file))
abort "Formato non riconosciuto (atteso basket-index-export)" unless export.is_a?(Hash) && export["format"] == "basket-index-export" && export["docs"].is_a?(Array)

prodotti = export["docs"].map { |d| d["data"] }.select { |d| d.is_a?(Hash) && d["kind"] == "product" }
per_ean = Hash.new { |h, k| h[k] = [] }
invalidi = []
senza_ean = 0
prodotti.each do |p|
  grezzo = (p["ean"] || p["gtin"]).to_s.strip
  if grezzo.empty?
    senza_ean += 1
    next
  end
  gtin = DataManager.normalizza_gtin(grezzo)
  gtin ? per_ean[gtin] << p : invalidi << grezzo
end

def descrizione_etichetta(p)
  eti = [p["brand"], p["product"], p["size"]].map { |v| v.to_s.strip }.reject(&:empty?).join(" ")
  p["product"].to_s.strip.empty? ? "" : eti
end

def kcal_incoerenti?(docs)
  kc = docs.map { |d| d.dig("nut", "kcal") }.compact.map(&:to_f)
  kc.size > 1 && (kc.max - kc.min) > 0.1 * [kc.max, 1].max
end

def scheda_da_etichetta(gtin, doc, descrizione)
  n = doc["nut"]
  return nil unless n.is_a?(Hash)

  {
    found: true, barcode: gtin, name: doc["product"].to_s, brand: doc["brand"].to_s, quantity: doc["size"].to_s,
    energy_kcal_100g: n["kcal"], sugars_100g: n["s"], saturated_fat_100g: n["sf"], salt_100g: n["salt"],
    source_note: "etichetta da foto (artifact)", descrizione: descrizione
  }.compact
end

conta = Hash.new(0)
incoerenti = []
DataManager.transazione(applica: apply) do
  per_ean.each do |gtin, docs|
    esiste = DB.get_first_row("SELECT descrizione, metadata_json FROM prodotti WHERE gtin = ?", [gtin])
    descr = docs.map { |d| descrizione_etichetta(d) }.find { |x| !x.empty? } ||
            docs.flat_map { |d| Array(d["names"]) }.map(&:to_s).find { |x| !x.strip.empty? }.to_s.strip
    incoerente = kcal_incoerenti?(docs)
    incoerenti << gtin if incoerente

    unless esiste
      DB.execute("INSERT INTO prodotti (gtin, descrizione, descrizione_origine, fonte) VALUES (?, ?, ?, 'artifact')",
                 [gtin, descr.empty? ? nil : descr, descr.empty? ? nil : "scontrino"])
      conta[:prodotti_nuovi] += 1
    end

    if (esiste.nil? || esiste["metadata_json"].to_s.empty?) && !incoerente
      doc_nut = docs.find { |d| d["nut"].is_a?(Hash) }
      scheda = doc_nut && scheda_da_etichetta(gtin, doc_nut, descr)
      if scheda
        DB.execute("UPDATE prodotti SET metadata_json = ?, fonte = COALESCE(NULLIF(fonte, ''), 'artifact') WHERE gtin = ?", [JSON.generate(scheda), gtin])
        conta[:schede_da_etichetta] += 1
      end
    end
    conta[:prodotti_gia_presenti] += 1 if esiste

    # Priorità del nome: preferiti > storico > scontrino. Prima dagli alias, che confrontano con la descrizione finale.
    origine = DataManager.riallinea_descrizione(gtin)
    conta[:"nome_da_#{origine}"] += 1 if origine

    docs.each do |d|
      Array(d["names"]).each do |nome|
        esito = DataManager.registra_alias_prodotto(gtin, nome, negozio: d["store"].to_s, fonte: "artifact")
        conta[esito == :nuovo ? :alias_nuovi : (esito == :esistente ? :alias_gia_presenti : :alias_scartati)] += 1
      end
    end
  end
end

puts "\n===== #{apply ? 'APPLICATO' : 'DRY-RUN (nessuna scrittura)'} su #{DB_PATH} ====="
puts "Documenti prodotto nell'export: #{prodotti.size} (senza EAN: #{senza_ean})"
puts "EAN validi distinti:            #{per_ean.size}"
puts "EAN con cifra di controllo errata: #{invalidi.size}#{invalidi.empty? ? '' : ' -> ' + invalidi.uniq.join(', ')}"
puts "EAN con etichette incoerenti:   #{incoerenti.size}#{incoerenti.empty? ? '' : ' -> ' + incoerenti.join(', ')}"
conta.each { |k, v| puts format("%-24s %d", k.to_s.tr("_", " "), v) }
puts "Per scrivere davvero: aggiungi --apply (fai prima una copia del DB)." unless apply

if openfood
  require File.expand_path("../models/open_food_facts_client", __dir__)
  user_agent = DataManager.user_agent_openfood
  abort "open_food_facts_user_agent non configurato" if user_agent.empty?

  # Da scaricare: nessuna scheda, scheda senza nome, o scheda minima ricavata dall'etichetta dell'artifact.
  def scheda_da_scaricare?(gtin)
    meta = JSON.parse(DB.get_first_value("SELECT metadata_json FROM prodotti WHERE gtin = ?", [gtin]).to_s)
    meta["name"].to_s.strip.empty? || !meta["source_note"].nil?
  rescue JSON::ParserError
    true
  end

  da_scaricare = per_ean.keys.select { |gtin| scheda_da_scaricare?(gtin) }
  puts "\nOpen Food Facts: #{da_scaricare.size} codici da scaricare"
  trovati = 0
  da_scaricare.each do |gtin|
    prodotto = OpenFoodFactsClient.lookup(gtin, user_agent: user_agent)
    if prodotto
      prima = DB.get_first_value("SELECT descrizione FROM prodotti WHERE gtin = ?", [gtin])
      DataManager.salva_scheda_prodotto(prodotto)
      DataManager.registra_alias_prodotto(gtin, prima, fonte: "descrizione_precedente")   # il nome sostituito non si perde
      trovati += 1
      puts "  + #{gtin} #{prodotto[:name]} (#{prodotto[:brand]})"
    else
      puts "  - #{gtin} non trovato"
    end
    sleep 1
  end
  puts "Schede scaricate: #{trovati} su #{da_scaricare.size}"
end
