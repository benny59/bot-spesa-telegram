# api_server.rb - HTTP daemon per l'app Android
# Esegui: ruby api_server.rb
# Richiede: gem install sinatra
require 'sinatra'
require 'json'
require 'set'
require 'fileutils'
require 'securerandom'
require 'faraday'
require_relative 'db'
require_relative 'models/lista'
require_relative 'models/whitelist'
require_relative 'handlers/storico_manager'

# Invia notifica Telegram al gruppo dopo la scopetta
def notifica_scopetta(gruppo_id, topic_id, user_id, articoli_rimasti)
  env   = DB.get_first_value("SELECT value FROM config WHERE key = 'environment'") || 'production'
  key   = env == 'production' ? 'token' : 'token_dev'
  token = DB.get_first_value("SELECT value FROM config WHERE key = ?", [key])
  return unless token

  chat_id = DataManager.get_real_chat_id(gruppo_id)
  return unless chat_id

  nome = DB.get_first_value(
    "SELECT first_name FROM user_names WHERE user_id = ?", [user_id]
  ) || 'Utente'

  testo = articoli_rimasti == 0 \
    ? "\u{1F6D2} <b>#{nome}</b> ha terminato la spesa."\
    : "\u{1F6D2} <b>#{nome}</b> ha terminato la spesa, controlla gli articoli rimasti."

  payload = { chat_id: chat_id, text: testo, parse_mode: 'HTML' }
  payload[:message_thread_id] = topic_id if topic_id.to_i != 0

  Faraday.post("https://api.telegram.org/bot#{token}/sendMessage") do |req|
    req.headers['Content-Type'] = 'application/json'
    req.body = payload.to_json
  end
rescue => e
  puts "\u26A0\uFE0F  Notifica scopetta fallita: #{e.message}"
end

configure do
  set :bind, '0.0.0.0'
  set :port, (ENV['SPESA_PORT'] || 4568).to_i   # 4567 è riservata a daze su Termux
  set :show_exceptions, false
  enable :logging
end

# --- Auth ---

def api_token
  DB.get_first_value("SELECT value FROM config WHERE key = 'api_token'")
end

before do
  content_type :json
  next if request.path_info == '/collega'  # bootstrap: nessun token richiesto
  next if request.path_info.start_with?('/me')  # recupero nome utente
  token = api_token
  next if token.nil? || token.strip.empty?

  auth = request.env['HTTP_AUTHORIZATION']
  halt 401, { error: 'Unauthorized' }.to_json unless auth == "Bearer #{token}"
end

error do
  { error: env['sinatra.error'].message }.to_json
end

# --- Helper ---

def json_body
  JSON.parse(request.body.read)
rescue JSON::ParserError
  halt 400, { error: 'JSON non valido' }.to_json
end

# --- Endpoints ---

get '/ping' do
  { status: 'ok', version: '1.0' }.to_json
end

get '/gruppi' do
  rows = DB.execute("SELECT id, nome, chat_id FROM gruppi ORDER BY nome")
  result = rows.map { |r| { id: r['id'], nome: r['nome'], chat_id: r['chat_id'] } }
  # Lista Personale: virtuale, per ogni utente filtra i propri articoli
  ([{ id: 0, nome: 'Lista Personale', chat_id: nil }] + result).to_json
end

get '/topics' do
  gruppo_id = params[:gruppo_id]&.to_i
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  # Lista Personale: nessun topic reale, solo voce fittizia
  if gruppo_id == 0
    return [{ topic_id: 0, nome: 'Personale' }].to_json
  end

  chat_id = DB.get_first_value("SELECT chat_id FROM gruppi WHERE id = ?", [gruppo_id])
  rows = DB.execute(
    "SELECT topic_id, nome FROM topics WHERE chat_id = ? ORDER BY nome",
    [chat_id]
  )
  risultato = rows.map { |r| { topic_id: r['topic_id'], nome: r['nome'] } }
  # Aggiungi Principale solo se topic_id=0 non è già nel DB (potrebbe avere un nome diverso)
  unless risultato.any? { |r| r[:topic_id] == 0 }
    risultato = [{ topic_id: 0, nome: 'Principale' }] + risultato
  end
  risultato.to_json
end

get '/lista' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  # Lista Personale: mostra solo i propri articoli
  user_id_q = params[:user_id]&.to_i || 0
  items = (gruppo_id == 0 && user_id_q != 0) \
    ? Lista.personale(user_id_q) \
    : Lista.tutti(gruppo_id, topic_id)

  # batch check quali item hanno foto
  item_ids = items.map { |i| i['id'] }
  foto_ids = if item_ids.any?
    ph = item_ids.map { '?' }.join(',')
    DB.execute("SELECT DISTINCT item_id FROM item_images WHERE item_id IN (#{ph})", item_ids)
      .map { |r| r['item_id'] }.to_set
  else
    Set.new
  end

  items.map do |i|
    {
      id:            i['id'],
      gruppo_id:     i['gruppo_id'],
      nome:          i['nome'],
      comprato:      i['comprato'].to_s,
      creato_da:     i['creato_da'],
      user_initials: i['user_initials'].to_s,
      creato_il:     i['creato_il'],
      has_foto:      foto_ids.include?(i['id'])
    }
  end.to_json
end

post '/lista' do
  body      = json_body
  gruppo_id = body['gruppo_id']&.to_i
  topic_id  = body['topic_id']&.to_i || 0
  testo     = body['nome'].to_s.strip
  user_id   = body['user_id']&.to_i || 0

  halt 400, { error: 'parametri mancanti' }.to_json if gruppo_id.nil? || testo.empty?

  DataManager.aggiungi_articoli(gruppo_id: gruppo_id, user_id: user_id, items_text: testo, topic_id: topic_id)
  status 201
  { ok: true }.to_json
end

patch '/lista/:id/toggle' do
  item_id   = params[:id].to_i
  body      = json_body
  gruppo_id = body['gruppo_id']&.to_i
  user_id   = body['user_id']&.to_i || 0

  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  result = Lista.toggle_comprato(gruppo_id, item_id, user_id)
  halt 404, { error: 'item non trovato' }.to_json if result.nil?
  { comprato: result.to_s }.to_json
end

# Rotta specifica PRIMA di quella parametrica per evitare conflitti
delete '/lista/comprati' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0
  user_id   = params[:user_id]&.to_i  || 0
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  # Lista Personale: scopetta solo i propri articoli comprati
  rimossi = if gruppo_id == 0 && user_id != 0
    target = DB.execute(
      "SELECT id FROM items WHERE gruppo_id=0 AND topic_id=? AND comprato!='' AND creato_da=?",
      [topic_id, user_id]
    ).map { |r| r['id'] }
    target.any? ? DataManager.esegui_scopetta(0, topic_id, target) : 0
  else
    DataManager.esegui_scopetta(gruppo_id, topic_id)
  end

  if rimossi > 0
    rimasti = DataManager.prendi_articoli_ordinati(gruppo_id, topic_id).size
    notifica_scopetta(gruppo_id, topic_id, user_id, rimasti)
  end

  { ok: true, rimossi: rimossi }.to_json
end

# Superscopetta: cancella tutti gli articoli PROPRI marcati in ogni gruppo
delete '/lista/comprati/ovunque' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0

  da_rimuovere = DataManager.articoli_da_superscopetta(user_id, false)
  halt 200, { ok: true, rimossi: 0 }.to_json if da_rimuovere.empty?

  # Raggruppa per (gruppo_id, topic_id) e chiama esegui_scopetta per ognuno
  per_gruppo = da_rimuovere.group_by { |i| [i['gruppo_id'], i['topic_id']] }
  rimossi = per_gruppo.sum do |(g_id, t_id), items|
    ids = items.map { |i| i['id'] }
    DataManager.esegui_scopetta(g_id, t_id, ids)
  end

  { ok: true, rimossi: rimossi }.to_json
end

delete '/lista/:id' do
  item_id   = params[:id].to_i
  gruppo_id = params[:gruppo_id]&.to_i

  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  # Verifica appartenenza al gruppo prima di procedere
  item = DB.get_first_row("SELECT id FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  halt 404, { error: 'item non trovato' }.to_json unless item

  DataManager.rimuovi_item_diretto(item_id)
  { ok: true }.to_json
end

# Checklist: suggerimenti dallo storico (top articoli del gruppo)
get '/checklist' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  items = StoricoManager.suggerimenti_per_checklist(gruppo_id, topic_id)
  items.map { |i| { nome: i['nome'], conteggio: i['conteggio'].to_i, in_lista: !i['in_lista'].nil? } }.to_json
end

# Checklist toggle: aggiunge o rimuove dalla lista attiva
post '/checklist/toggle' do
  body      = json_body
  gruppo_id = body['gruppo_id']&.to_i
  topic_id  = body['topic_id']&.to_i || 0
  nome      = body['nome'].to_s.strip
  in_lista  = body['in_lista'] == true
  user_id   = body['user_id']&.to_i || 0

  halt 400, { error: 'parametri mancanti' }.to_json if gruppo_id.nil? || nome.empty?

  if in_lista
    item_id = DB.get_first_value(
      "SELECT id FROM items WHERE gruppo_id = ? AND topic_id = ? AND LOWER(nome) = ? AND (comprato IS NULL OR comprato = '')",
      [gruppo_id, topic_id, nome.downcase]
    )
    DataManager.rimuovi_item_diretto(item_id) if item_id
  else
    DataManager.ripristina_da_checklist(gruppo_id, topic_id, nome, user_id)
  end

  { ok: true, in_lista: !in_lista }.to_json
end

get '/foto/:item_id' do
  item_id = params[:item_id].to_i

  img = DB.get_first_row(
    "SELECT file_id, file_unique_id FROM item_images WHERE item_id = ? ORDER BY id DESC LIMIT 1",
    [item_id]
  )
  halt 404, { error: 'Nessuna foto' }.to_json unless img

  cache_dir  = File.join(File.dirname(__FILE__), 'data', 'foto_cache')
  cache_path = File.join(cache_dir, "#{img['file_unique_id']}.jpg")

  unless File.exist?(cache_path)
    # I file locali non richiedono chiamate Telegram
    if img['file_id'].to_s.start_with?('local:')
      halt 404, { error: 'foto locale non trovata' }.to_json
    end

    # I file_id sono specifici del bot che li ha ricevuti: proviamo prima token_dev poi token
    tokens = ['token_dev', 'token']
      .map { |k| DB.get_first_value("SELECT value FROM config WHERE key = ?", [k]) }
      .compact
    tokens << ENV['TELEGRAM_BOT_TOKEN'] if ENV['TELEGRAM_BOT_TOKEN']
    halt 503, { error: 'Token bot non configurato' }.to_json if tokens.empty?

    tg   = Faraday.new('https://api.telegram.org')
    meta = nil
    tokens.each do |tok|
      res = JSON.parse(tg.get("/bot#{tok}/getFile", { file_id: img['file_id'] }).body)
      if res['ok']
        meta = res.merge('_token' => tok)
        break
      end
    end
    halt 502, { error: 'Nessun token può accedere al file' }.to_json unless meta

    FileUtils.mkdir_p(cache_dir)
    bytes = tg.get("/file/bot#{meta['_token']}/#{meta['result']['file_path']}").body
    File.binwrite(cache_path, bytes)
  end

  content_type 'image/jpeg'
  File.binread(cache_path)
end

post '/lista/:item_id/foto' do
  item_id = params[:item_id].to_i

  halt 404, { error: 'item non trovato' }.to_json unless
    DB.get_first_value("SELECT id FROM items WHERE id = ?", [item_id])

  image_data = params[:file] ? params[:file][:tempfile].read : request.body.read
  halt 400, { error: 'nessun file ricevuto' }.to_json if image_data.nil? || image_data.empty?

  uuid      = SecureRandom.uuid
  cache_dir = File.join(File.dirname(__FILE__), 'data', 'foto_cache')
  FileUtils.mkdir_p(cache_dir)
  File.binwrite(File.join(cache_dir, "#{uuid}.jpg"), image_data)

  DB.execute(
    "INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
    [item_id, "local:#{uuid}", uuid]
  )
  status 201
  { ok: true }.to_json
end

# Dati utente per il collegamento app (esentato da auth: usato anche per recupero nome)
get '/me' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  row = DB.get_first_row(
    "SELECT first_name, last_name FROM user_names WHERE user_id = ?", [user_id]
  )
  halt 404, { error: 'utente non trovato' }.to_json unless row
  { first_name: row['first_name'].to_s, last_name: row['last_name'].to_s }.to_json
end

# Helper condiviso per serializzare un item verso l'app Android
def serializza_item(i, nome_gruppo: '')
  # Combina gruppo e topic in un'unica etichetta
  t_nome = i['nome_topic'].to_s.strip
  gruppo_label = nome_gruppo.empty? ? '' : (t_nome.empty? ? nome_gruppo : "#{nome_gruppo} \u2022 #{t_nome}")
  {
    id:            i['id'],
    gruppo_id:     i['gruppo_id'],
    nome:          i['nome'],
    comprato:      i['comprato'].to_s,
    creato_da:     i['creato_da'],
    user_initials: i['user_initials'].to_s,
    creato_il:     i['creato_il'],
    has_foto:      false,
    nome_gruppo:   gruppo_label
  }
end

# Vista trasversale: tutti gli articoli dei gruppi dell'utente (riusa DataManager)
get '/lista/tutti' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  items = DataManager.prendi_tutto_ovunque(user_id)
  items.map { |i| serializza_item(i, nome_gruppo: i['nome_gruppo'].to_s) }.to_json
end

# Vista trasversale: solo i miei articoli in tutti i gruppi
get '/lista/miei' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  items = DataManager.prendi_miei_ovunque(user_id)
  items.map { |i| serializza_item(i, nome_gruppo: i['nome_gruppo'].to_s) }.to_json
end

# Collega account Telegram tramite PIN generato dal bot
post '/collega' do
  body = json_body
  pin  = body['pin'].to_s.strip
  halt 400, { error: 'pin mancante' }.to_json if pin.empty?

  # Scade dopo 10 minuti
  row = DB.get_first_row(
    "SELECT user_id, first_name FROM link_pins WHERE pin = ? AND datetime(created_at, '+10 minutes') > datetime('now')",
    [pin]
  )
  halt 404, { error: 'PIN non valido o scaduto' }.to_json unless row

  DB.execute("DELETE FROM link_pins WHERE pin = ?", [pin])
  { user_id: row['user_id'], first_name: row['first_name'] }.to_json
end

get '/carte' do
  gruppo_id = params[:gruppo_id]&.to_i
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  rows = DB.execute(
    "SELECT c.id, c.nome, c.codice, c.formato
     FROM carte_fedelta c
     JOIN gruppo_carte_collegamenti g ON c.id = g.carta_id
     WHERE g.gruppo_id = ?
     ORDER BY c.nome",
    [gruppo_id]
  )
  rows.map { |r| { id: r['id'], nome: r['nome'], codice: r['codice'], formato: r['formato'] } }.to_json
end
