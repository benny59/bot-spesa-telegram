require_relative "../models/promemoria_ics"

adesso = Time.utc(2026, 10, 30, 8, 0, 0)
ics = PromemoriaIcs.genera(
  titolo: "Pagare bollo; auto, targa AB123CD",
  inizio: "2026-11-05T09:30",
  luogo: "Poste, Via Roma 1",
  descrizione: "Portare\nil libretto",
  preavviso_minuti: 2880,
  uid: "test@botspesa",
  adesso: adesso
)

raise "Fine riga non CRLF" unless ics.end_with?("END:VCALENDAR\r\n") && !ics.gsub("\r\n", "").include?("\n")
raise "Inizio errato" unless ics.include?("DTSTART;TZID=Europe/Rome:20261105T093000\r\n")
raise "Fine errata" unless ics.include?("DTEND;TZID=Europe/Rome:20261105T103000\r\n")
raise "DTSTAMP errato" unless ics.include?("DTSTAMP:20261030T080000Z\r\n")
raise "Escape titolo errato" unless ics.include?("SUMMARY:Pagare bollo\\; auto\\, targa AB123CD\r\n")
raise "Escape luogo errato" unless ics.include?("LOCATION:Poste\\, Via Roma 1\r\n")
raise "Escape a capo errato" unless ics.include?("DESCRIPTION:Portare\\nil libretto\r\n")
raise "Allarme errato" unless ics.include?("TRIGGER:-P2D\r\n")
raise "VTIMEZONE mancante" unless ics.include?("BEGIN:VTIMEZONE\r\nTZID:Europe/Rome\r\n")

raise "Preavviso ore errato" unless PromemoriaIcs.durata_iso(90) == "PT1H30M"
raise "Preavviso giorno+ore errato" unless PromemoriaIcs.durata_iso(1500) == "P1DT1H"

senza = PromemoriaIcs.genera(titolo: "Solo titolo", inizio: "2026-12-31T23:30", adesso: adesso)
raise "Allarme non richiesto presente" if senza.include?("VALARM")
raise "Luogo vuoto presente" if senza.include?("LOCATION")
raise "Fine oltre mezzanotte errata" unless senza.include?("DTEND;TZID=Europe/Rome:20270101T003000\r\n")

lunga = PromemoriaIcs.genera(titolo: "Titolo", inizio: "2026-11-05T09:30",
                             descrizione: "è" * 100, adesso: adesso)
lunga.split("\r\n").each do |riga|
  raise "Riga oltre 75 ottetti" if riga.bytesize > 75
end
raise "Unfolding perde testo" unless lunga.gsub("\r\n ", "").include?("DESCRIPTION:#{'è' * 100}\r\n")

[
  { titolo: "", inizio: "2026-11-05T09:30" },
  { titolo: "x", inizio: "domani" },
  { titolo: "x", inizio: "2026-13-45T09:30" },
  { titolo: "x", inizio: "2026-11-05T09:30", preavviso_minuti: -5 },
  { titolo: "x", inizio: "2026-11-05T09:30", preavviso_minuti: 10_000_000 }
].each do |args|
  begin
    PromemoriaIcs.genera(**args)
    raise "Input non valido accettato: #{args}"
  rescue PromemoriaIcs::Error
    # atteso
  end
end

raise "Nome file errato" unless PromemoriaIcs.nome_file("Visita è dal dottore!") == "Visita_e_dal_dottore.ics"
raise "Nome file di ripiego errato" unless PromemoriaIcs.nome_file("???") == "promemoria.ics"

puts "PromemoriaIcs: OK"
