#!/usr/bin/env ruby
# frozen_string_literal: true

# Integra i backup dei preferiti di TUTTI gli utenti con ciò che il server sa (GTIN, link Yuka).
#
#   ruby scripts/integra_preferiti.rb                       # dry-run: elenca cosa cambierebbe
#   ruby scripts/integra_preferiti.rb --apply               # riscrive i backup dei preferiti
#   ruby scripts/integra_preferiti.rb --apply --notifica    # ... e avvisa su Telegram gli utenti modificati
#   SPESA_DB=copia.db ruby scripts/integra_preferiti.rb     # su una copia
#
# Regole:
#  - nome, categoria e foto del preferito NON cambiano mai: si completano solo i campi vuoti.
#  - GTIN mancante: si ricava dal link Yuka (item/storico con lo stesso link) o da un nome IDENTICO
#    (normalizzato) alla descrizione/alias di un solo prodotto. I nomi solo "simili" vengono segnalati, mai applicati.
#  - link Yuka mancante: si prende da item/storico con lo stesso GTIN.
#  - il nome del preferito diventa la descrizione del prodotto (priorità massima, vedi imposta_descrizione).
#  - il messaggio Telegram parte solo con --notifica insieme a --apply, solo a chi ha subito modifiche o ha duplicati;
#    elenca anche i preferiti duplicati (stesso GTIN, link Yuka o nome).

require "json"
require "time"

apply = ARGV.delete("--apply")
notifica = ARGV.delete("--notifica")
abort "--notifica richiede --apply" if notifica && !apply

require File.expand_path("../db", __dir__)

righe = DB.execute("SELECT id, creato_da, link_url FROM items WHERE nome = ? AND deleted = 0 ORDER BY id", [DataManager::CONFIG_PREFERITI_NOME])
riepilogo = []
simili_tot = []

DataManager.transazione(applica: apply) do
    righe.each do |riga|
      backup = begin
        JSON.parse(riga["link_url"].to_s)
      rescue JSON::ParserError
        nil
      end
      next unless backup.is_a?(Hash) && backup["favorites"].is_a?(Array)

      cambiati = []
      nuovi = backup["favorites"].map do |fav|
        nuovo, modifiche, simili = DataManager.integra_preferito(fav)
        cambiati << [fav["description"], modifiche] unless modifiche.empty?
        simili_tot << [riga["creato_da"], fav["description"], simili] unless simili.empty?
        nuovo
      end

      riepilogo << { utente: riga["creato_da"], totale: nuovi.size, cambiati: cambiati, ultimo_backup: backup["lastBackupAt"],
                     duplicati: DataManager.duplicati_preferiti(nuovi) }
      next if cambiati.empty?

      backup["favorites"] = nuovi
      backup["integratoIl"] = Time.now.utc.iso8601
      DB.execute("UPDATE items SET link_url = ? WHERE id = ?", [JSON.generate(backup), riga["id"]])
    end
end

puts "\n===== #{apply ? 'APPLICATO' : 'DRY-RUN (nessuna scrittura)'} su #{DB_PATH} ====="
puts "Backup preferiti trovati: #{righe.size}"
riepilogo.each do |r|
  puts "\nUtente #{r[:utente]}: #{r[:totale]} preferiti, #{r[:cambiati].size} integrati (ultimo backup #{r[:ultimo_backup]})"
  r[:cambiati].each { |nome, mod| puts "  + #{nome}: #{mod.join(', ')}" }
  r[:duplicati].each { |g| puts "  = duplicati: tieni «#{g.first}», elimina #{g.drop(1).join(' / ')}" }
end
unless simili_tot.empty?
  puts "\nNomi SOLO simili (non applicati, da decidere a mano):"
  simili_tot.each { |u, nome, s| puts "  ? [#{u}] #{nome} ~ #{s.map { |g, d| "#{g} #{d}" }.join(' | ')}" }
end

if notifica
  require "telegram/bot"
  client = Telegram::Bot::Client.new(DataManager.token_telegram_attivo)
  riepilogo.reject { |r| r[:cambiati].empty? && r[:duplicati].empty? }.each do |r|
    testo = +""
    unless r[:cambiati].empty?
      testo << "🔄 Ho integrato #{r[:cambiati].size} dei tuoi preferiti (codice a barre / link Yuka).\n" \
               "Per caricarli apri l'app → Preferiti → Ripristina.\n" \
               "⚠️ Il ripristino sostituisce i preferiti del telefono: se dopo il backup del #{r[:ultimo_backup].to_s[0, 10]} " \
               "ne hai aggiunti di nuovi, non ripristinare e avvisami.\n"
    end
    unless r[:duplicati].empty?
      testo << "\n👯 Possibili duplicati tra i tuoi preferiti (stesso prodotto):\n"
      r[:duplicati].each { |g| testo << "• tieni «#{g.first}» (il più completo), elimina: #{g.drop(1).join(' / ')}\n" }
    end
    begin
      client.api.send_message(chat_id: r[:utente], text: testo)
      puts "Messaggio inviato a #{r[:utente]}"
    rescue StandardError => e
      puts "Messaggio NON inviato a #{r[:utente]}: #{e.message}"
    end
    sleep 1
  end
end
puts "\nPer scrivere davvero: aggiungi --apply (dopo una copia del DB)." unless apply
