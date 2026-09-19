#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'
require 'open-uri'

# Verifica che sia stato passato il GTIN come argomento
if ARGV.empty?
  puts "Uso: ruby openfood.rb <GTIN>"
  puts "Esempio: ruby openfood.rb 3017620422003"
  exit 1
end

gtin = ARGV[0]
api_url = URI("https://world.openfoodfacts.org/api/v2/product/#{gtin}.json")

begin
  puts "Interrogazione del database Open Food Facts per il GTIN: #{gtin}..."
  response = Net::HTTP.get(api_url)
  data = JSON.parse(response)

  if data['status'] != 1
    puts "Errore: Prodotto non trovato nel database per il codice GTIN specificato."
    exit 1
  end

  product = data['product']
  
  # Estrazione dei dati principali
  product_name = product['product_name'] || product['product_name_it'] || "Nome non disponibile"
  brands = product['brands'] || "Marchio/Azienda non disponibile"
  manufacturing_places = product['manufacturing_places'] || "Non specificato"
  image_url = product['image_front_url'] || product['image_url']

  # Output della sintesi aziendale e del prodotto
  puts "\n--- SINTESI PRODOTTO & AZIENDA ---"
  puts "Prodotto: #{product_name}"
  puts "Azienda / Marchio: #{brands}"
  puts "Luogo di produzione: #{manufacturing_places}"

  # Download e salvataggio della fotografia
  if image_url && !image_url.empty?
    puts "Scaricamento dell'immagine in corso..."
    image_data = URI.open(image_url).read
    filename = "prodotto_#{gtin}.jpg"
    
    File.open(filename, 'wb') do |file|
      file.write(image_data)
    end
    puts "Fotografia salvata con successo come: #{filename}"
  else
    puts "Nessuna immagine disponibile per questo prodotto."
  end

rescue StandardError => e
  puts "Si è verificato un errore durante la richiesta: #{e.message}"
  exit 1
end
