require 'securerandom'
require 'time'

# Genera un promemoria una tantum in formato iCalendar (.ics) da inviare su Telegram:
# chi lo riceve lo apre e lo salva nel calendario del telefono.
class PromemoriaIcs
  class Error < StandardError; end

  TZID = 'Europe/Rome'.freeze
  DURATA_SECONDI = 3600
  MAX_PREAVVISO_MINUTI = 365 * 24 * 60

  # Regole CET/CEST in vigore dal 1996, così il calendario conosce l'ora legale.
  VTIMEZONE = [
    'BEGIN:VTIMEZONE',
    "TZID:#{TZID}",
    'BEGIN:DAYLIGHT',
    'TZOFFSETFROM:+0100',
    'TZOFFSETTO:+0200',
    'TZNAME:CEST',
    'DTSTART:19700329T020000',
    'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
    'END:DAYLIGHT',
    'BEGIN:STANDARD',
    'TZOFFSETFROM:+0200',
    'TZOFFSETTO:+0100',
    'TZNAME:CET',
    'DTSTART:19701025T030000',
    'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
    'END:STANDARD',
    'END:VTIMEZONE'
  ].freeze

  # inizio: orario locale "YYYY-MM-DDTHH:MM" (come da <input type="datetime-local">)
  # preavviso_minuti: 0 = nessun allarme
  def self.genera(titolo:, inizio:, luogo: '', descrizione: '', preavviso_minuti: 0,
                  uid: nil, adesso: Time.now.utc)
    titolo = titolo.to_s.strip
    raise Error, 'titolo mancante' if titolo.empty?

    inizio_locale = parse_locale(inizio)
    fine_locale = inizio_locale + DURATA_SECONDI
    preavviso = preavviso_minuti.to_i
    raise Error, 'preavviso non valido' if preavviso.negative? || preavviso > MAX_PREAVVISO_MINUTI

    righe = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Bot Spesa//Promemoria//IT',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      *VTIMEZONE,
      'BEGIN:VEVENT',
      "UID:#{uid || "#{SecureRandom.uuid}@botspesa"}",
      "DTSTAMP:#{adesso.utc.strftime('%Y%m%dT%H%M%SZ')}",
      "DTSTART;TZID=#{TZID}:#{formato_locale(inizio_locale)}",
      "DTEND;TZID=#{TZID}:#{formato_locale(fine_locale)}",
      "SUMMARY:#{escape(titolo)}"
    ]
    righe << "LOCATION:#{escape(luogo)}" unless luogo.to_s.strip.empty?
    righe << "DESCRIPTION:#{escape(descrizione)}" unless descrizione.to_s.strip.empty?
    if preavviso.positive?
      righe.push('BEGIN:VALARM', 'ACTION:DISPLAY', "DESCRIPTION:#{escape(titolo)}",
                 "TRIGGER:-#{durata_iso(preavviso)}", 'END:VALARM')
    end
    righe.push('END:VEVENT', 'END:VCALENDAR')

    righe.map { |riga| piega(riga) }.join("\r\n") + "\r\n"
  end

  # Nome file sicuro derivato dal titolo
  def self.nome_file(titolo)
    base = titolo.to_s.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, '')
                 .gsub(/[^A-Za-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')[0, 40]
    "#{base.empty? ? 'promemoria' : base}.ics"
  end

  # Orario "naive" (senza fuso) rappresentato come Time UTC solo per l'aritmetica
  def self.parse_locale(valore)
    m = valore.to_s.strip.match(/\A(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::\d{2})?\z/)
    raise Error, 'data e ora non valide' unless m

    Time.utc(*m.captures.map(&:to_i))
  rescue ArgumentError
    raise Error, 'data e ora non valide'
  end

  def self.formato_locale(tempo)
    tempo.strftime('%Y%m%dT%H%M%S')
  end

  def self.durata_iso(minuti)
    giorni, resto = minuti.divmod(1440)
    ore, min = resto.divmod(60)
    iso = +'P'
    iso << "#{giorni}D" if giorni.positive?
    if ore.positive? || min.positive?
      iso << 'T'
      iso << "#{ore}H" if ore.positive?
      iso << "#{min}M" if min.positive?
    end
    iso
  end

  def self.escape(testo)
    testo.to_s.strip.gsub('\\', '\\\\\\\\').gsub(';', '\;').gsub(',', '\,')
         .gsub(/\r\n|\r|\n/, '\n')
  end

  # RFC 5545: righe max 75 ottetti, continuazione con CRLF + spazio, senza spezzare un carattere UTF-8
  def self.piega(riga)
    return riga if riga.bytesize <= 75

    parti = []
    corrente = +''
    limite = 75
    riga.each_char do |c|
      if corrente.bytesize + c.bytesize > limite
        parti << corrente
        corrente = +''
        limite = 74
      end
      corrente << c
    end
    parti << corrente
    parti.join("\r\n ")
  end
end
