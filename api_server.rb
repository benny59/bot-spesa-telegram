# api_server.rb - HTTP daemon per l'app Android
# Esegui: ruby api_server.rb
# Richiede: gem install sinatra
require 'sinatra'
require 'json'
require 'set'
require 'fileutils'
require 'securerandom'
require 'cgi'
require 'faraday'
require 'telegram/bot'
require_relative 'db'
require_relative 'models/lista'
require_relative 'models/whitelist'
require_relative 'models/barcode_scanner'
require_relative 'models/carte_fedelta'
require_relative 'models/open_food_facts_client'
require_relative 'handlers/storico_manager'
require_relative 'models/item_action_message'

# Helper base: invia qualsiasi messaggio a un gruppo/topic Telegram
def telegram_token_attivo
  env = DB.get_first_value("SELECT value FROM config WHERE key = 'environment'") || 'production'
  key = env == 'production' ? 'token' : 'token_dev'
  DB.get_first_value("SELECT value FROM config WHERE key = ?", [key]) || ENV['TELEGRAM_BOT_TOKEN']
end

def notifica_gruppo(gruppo_id, topic_id, testo)
  return if gruppo_id.to_i == 0

  token = telegram_token_attivo
  return unless token

  chat_id = DataManager.get_real_chat_id(gruppo_id)
  return unless chat_id

  payload = { chat_id: chat_id, text: testo, parse_mode: 'HTML', disable_notification: true }
  payload[:message_thread_id] = topic_id if topic_id.to_i != 0

  Faraday.post("https://api.telegram.org/bot#{token}/sendMessage") do |req|
    req.headers['Content-Type'] = 'application/json'
    req.body = payload.to_json
  end
rescue => e
  puts "\u26A0\uFE0F  Notifica gruppo fallita: #{e.message}"
end

# Invia notifica Telegram al gruppo dopo la scopetta
def notifica_scopetta(gruppo_id, topic_id, user_id, comprati: [], cancellati: [])
  nome = DB.get_first_value(
    "SELECT first_name FROM user_names WHERE user_id = ?", [user_id]
  ) || 'Utente'
  testo = StoricoManager.notifica_scopetta_html(nome, comprati: comprati, cancellati: cancellati)
  notifica_gruppo(gruppo_id, topic_id, testo)
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

def item_accessibile!(item_id, user_id)
  halt 400, { error: 'user_id mancante' }.to_json if user_id.to_i == 0

  item = Lista.trova(item_id)
  halt 404, { error: 'item non trovato' }.to_json unless item

  consentito = if item['gruppo_id'].to_i == 0
    item['creato_da'].to_i == user_id.to_i
  else
    DataManager.utente_ha_accesso_al_gruppo?(user_id, item['gruppo_id'])
  end
  halt 403, { error: 'accesso negato' }.to_json unless consentito
  item
end

# Rileva il formato barcode dal codice (stesso logic del bot, senza dipendenze barby)
def identifica_formato_codice(codice)
  c = codice.to_s.gsub(/\s/, '')
  return 'NESSUNO' if c.empty?
  return 'EAN13'  if c =~ /^\d{13}$/
  return 'EAN8'   if c =~ /^\d{8}$/
  return 'UPCA'   if c =~ /^\d{12}$/
  return 'ITF'    if c =~ /^\d{14}$/
  'CODE128'
end

# --- Endpoints ---

get '/ping' do
  { status: 'ok', version: '1.0' }.to_json
end

get '/prodotti/:barcode/anteprima' do
  product_scan_enabled = DB.get_first_value(
    "SELECT value FROM config WHERE key = ?",
    ['product_scan_enabled']
  ).to_s.strip.downcase
  halt 404, { error: 'funzione non disponibile' }.to_json if product_scan_enabled == 'false'

  barcode = params[:barcode].to_s
  halt 400, { error: 'barcode non valido' }.to_json unless barcode.match?(/\A\d{8,14}\z/)

  user_agent = DB.get_first_value(
    "SELECT value FROM config WHERE key = ?",
    ['open_food_facts_user_agent']
  ).to_s.strip
  halt 503, { error: 'open_food_facts_user_agent non configurato' }.to_json if user_agent.empty?

  product = OpenFoodFactsClient.lookup(barcode, user_agent: user_agent)
  halt 404, { found: false, barcode: barcode }.to_json unless product

  product.to_json
end

get '/gruppi' do
  user_id = params[:user_id]&.to_i
  rows = if user_id && user_id != 0
    DataManager.prendi_gruppi_accessibili(user_id)
  else
    DB.execute("SELECT id, nome, chat_id FROM gruppi ORDER BY nome")
  end
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
      topic_id:      i['topic_id'],
      nome:          i['nome'],
      link_url:      i['link_url'].to_s,
      categoria_id:  i['categoria_id']&.to_i,
      categoria_nome: i['categoria_nome'].to_s,
      comprato:      i['comprato'].to_s.empty? ? '' : i['buyer_initials'].to_s,
      buyer_initials: i['buyer_initials'].to_s,
      creato_da:     i['creato_da'],
      user_initials: i['user_initials'].to_s,
      creato_il:     i['creato_il'],
      deleted:       i['deleted'].to_i == 1,
      disponibile:   i['disponibile'].to_i != 0,
      has_foto:      foto_ids.include?(i['id'])
    }
  end.to_json
end

get '/categorie' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0

  categorie = if gruppo_id && gruppo_id != 0
    DataManager.categorie_per_android(gruppo_id, topic_id)
  elsif topic_id && topic_id != 0
    DataManager.categorie_per_android(nil, topic_id)
  else
    DataManager.categorie_per_android
  end

  categorie.map { |r| { id: r[:id].to_i, nome: r[:nome].to_s } }.to_json
end

post '/lista' do
  body      = json_body
  gruppo_id = body['gruppo_id']&.to_i
  topic_id  = body['topic_id']&.to_i || 0
  testo     = body['nome'].to_s.strip
  link_url  = body['link_url'].to_s.strip
  split_items = body.key?('split_items') ? !!body['split_items'] : true
  categoria_id = body['categoria_id']&.to_i
  user_id   = body['user_id']&.to_i || 0

  halt 400, { error: 'parametri mancanti' }.to_json if gruppo_id.nil? || testo.empty?
  if gruppo_id != 0
    consentito = DataManager.utente_ha_accesso_al_gruppo?(user_id, gruppo_id)
    halt 403, { error: 'accesso negato' }.to_json unless consentito
  end

  item_ids = DataManager.aggiungi_articoli(
    gruppo_id: gruppo_id,
    user_id: user_id,
    items_text: testo,
    topic_id: topic_id,
    link_url: link_url,
    split_items: split_items,
    categoria_id: categoria_id
  )

  if gruppo_id != 0 && user_id != 0
    nome_utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || 'Utente'
    notifica_gruppo(gruppo_id, topic_id, "\u2795 <b>#{nome_utente}</b> ha aggiunto: #{testo}")
  end

  status 201
  { ok: true, item_ids: item_ids }.to_json
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

patch '/lista/:id' do
  item_id = params[:id].to_i
  body = json_body
  user_id = body['user_id']&.to_i || 0
  nome = body['nome'].to_s.strip
  categoria_id = body['categoria_id']
  halt 400, { error: 'nome mancante' }.to_json if nome.empty?

  item = item_accessibile!(item_id, user_id)
  halt 404, { error: 'item non trovato' }.to_json unless Lista.modifica_nome(item_id, nome)

  if categoria_id
    categoria_id_i = categoria_id.to_i
    if categoria_id_i > 0
      categoria = DB.get_first_row("SELECT id FROM categorie WHERE id = ?", [categoria_id_i])
      Lista.aggiorna_categoria(item_id, categoria_id_i) if categoria
    else
      Lista.aggiorna_categoria(item_id, nil)
    end
  end

  if item['gruppo_id'].to_i != 0
    utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || 'Utente'
    vecchia_categoria = item['categoria_id'] ? DB.get_first_value("SELECT nome FROM categorie WHERE id = ?", [item['categoria_id']]) : nil
    nuova_categoria = categoria_id_i && categoria_id_i > 0 ? DB.get_first_value("SELECT nome FROM categorie WHERE id = ?", [categoria_id_i]) : nil

    notifica_gruppo(
      item['gruppo_id'], item['topic_id'],
      DataManager.build_item_edit_message(utente, nome, item['nome'].to_s, nome, vecchia_categoria, nuova_categoria)
    )
  end

  { ok: true, nome: nome }.to_json
end

patch '/lista/:id/topic' do
  item_id = params[:id].to_i
  body = json_body
  user_id = body['user_id']&.to_i || 0
  target_gruppo_id = body['gruppo_id']&.to_i
  topic_id = body['topic_id']&.to_i
  halt 400, { error: 'topic_id mancante' }.to_json if topic_id.nil?
  halt 400, { error: 'gruppo_id mancante' }.to_json if target_gruppo_id.nil?

  item = item_accessibile!(item_id, user_id)
  current_gruppo_id = item['gruppo_id'].to_i

  if target_gruppo_id == 0
    halt 400, { error: 'La lista personale usa topic_id 0' }.to_json unless topic_id == 0
    halt 403, { error: 'accesso negato alla lista personale' }.to_json unless item['creato_da'].to_i == user_id.to_i
  else
    halt 404, { error: 'gruppo di destinazione non trovato' }.to_json unless DB.get_first_value("SELECT 1 FROM gruppi WHERE id = ?", [target_gruppo_id])
    halt 403, { error: 'accesso negato al gruppo di destinazione' }.to_json unless DataManager.utente_ha_accesso_al_gruppo?(user_id, target_gruppo_id)

    if topic_id != 0
      chat_id = DB.get_first_value("SELECT chat_id FROM gruppi WHERE id = ?", [target_gruppo_id])
      topic_valido = DB.get_first_value(
        "SELECT 1 FROM topics WHERE chat_id = ? AND topic_id = ?",
        [chat_id, topic_id]
      )
      halt 404, { error: 'topic non trovato' }.to_json unless topic_valido
    end
  end

  halt 404, { error: 'item non trovato' }.to_json unless Lista.sposta_topic(item_id, target_gruppo_id, topic_id)

  utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || 'Utente'
  notifica_gruppo(current_gruppo_id, item['topic_id'], DataManager.build_item_action_message(utente, item['nome'], 'spostato')) unless current_gruppo_id == 0
  notifica_gruppo(target_gruppo_id, topic_id, DataManager.build_item_action_message(utente, item['nome'], 'spostato_qui')) unless target_gruppo_id == 0
  { ok: true, gruppo_id: target_gruppo_id, topic_id: topic_id }.to_json
end

# Rotta specifica PRIMA di quella parametrica per evitare conflitti
delete '/lista/comprati' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0
  user_id   = params[:user_id]&.to_i  || 0
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  acquistati = if gruppo_id == 0 && user_id != 0
    DB.execute(
      "SELECT id, nome FROM items WHERE gruppo_id=0 AND topic_id=? AND comprato!='' AND creato_da=?",
      [topic_id, user_id]
    )
  else
    DB.execute(
      "SELECT id, nome FROM items WHERE gruppo_id=? AND topic_id=? AND comprato!=''",
      [gruppo_id, topic_id]
    )
  end

  cancellati = DB.execute(
    "SELECT id, nome FROM items WHERE gruppo_id=? AND topic_id=? AND deleted = 1",
    [gruppo_id, topic_id]
  )

  # Lista Personale: scopetta solo i propri articoli comprati
  rimossi = if gruppo_id == 0 && user_id != 0
    target = (acquistati + cancellati).map { |r| r['id'] }
    target.any? ? DataManager.esegui_scopetta(0, topic_id, target) : 0
  else
    DataManager.esegui_scopetta(gruppo_id, topic_id)
  end

  if rimossi > 0
    notifica_scopetta(
      gruppo_id,
      topic_id,
      user_id,
      comprati: acquistati.map { |item| item['nome'] },
      cancellati: cancellati.map { |item| item['nome'] }
    )
  end

  { ok: true, rimossi: rimossi }.to_json
end

# Superscopetta: cancella in ogni gruppo gli articoli marcati dall'utente
delete '/lista/comprati/ovunque' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0

  da_rimuovere = DataManager.articoli_da_superscopetta(user_id, false)
  halt 200, { ok: true, rimossi: 0 }.to_json if da_rimuovere.empty?

  # Raggruppa per (gruppo_id, topic_id) e chiama esegui_scopetta per ognuno
  per_gruppo = da_rimuovere.group_by { |i| [i['gruppo_id'], i['topic_id']] }
  rimossi = per_gruppo.sum do |(g_id, t_id), items|
    ids = items.map { |i| i['id'] }
    eliminati = DataManager.esegui_scopetta(g_id, t_id, ids)
    if eliminati > 0
      comprati = items.select { |i| i['comprato'].to_s.strip != '' }.map { |item| item['nome'] }
      cancellati = items.reject { |i| i['comprato'].to_s.strip != '' }.map { |item| item['nome'] }
      notifica_scopetta(g_id, t_id, user_id, comprati: comprati, cancellati: cancellati)
    end
    eliminati
  end

  { ok: true, rimossi: rimossi }.to_json
end

get '/storico/acquisti' do
  gruppo_id = params[:gruppo_id]&.to_i
  topic_id  = params[:topic_id]&.to_i || 0
  limite    = [[params[:limite].to_i, 1].max, 50].min
  limite    = 20 if params[:limite].nil?
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  StoricoManager.ultimi_acquisti(gruppo_id, topic_id, limite).map { |acquisto|
    {
      id:           acquisto['id'],
      nome:         acquisto['nome'],
      link_url:     acquisto['link_url'],
      creatore:     acquisto['creato_da'] ? acquisto['creatore'] : nil,
      acquirente:   acquisto['comprato_da'] ? acquisto['acquirente'] : nil,
      updated_at:   acquisto['updated_at'],
      conteggio:    acquisto['conteggio']
    }
  }.to_json
end

delete '/lista/:id' do
  item_id   = params[:id].to_i
  gruppo_id = params[:gruppo_id]&.to_i
  user_id   = params[:user_id]&.to_i || 0

  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  item = DB.get_first_row("SELECT id, nome, topic_id FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  halt 404, { error: 'item non trovato' }.to_json unless item

  DataManager.soft_delete_item(item_id)

  if gruppo_id != 0 && user_id != 0
    nome_utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || 'Utente'
    notifica_gruppo(gruppo_id, item['topic_id'], DataManager.build_item_action_message(nome_utente, item['nome'], 'soft_delete'))
  end

  { ok: true, soft_deleted: true }.to_json
end

post '/lista/:id/restore' do
  item_id   = params[:id].to_i
  gruppo_id = params[:gruppo_id]&.to_i

  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  item = DB.get_first_row("SELECT id FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  halt 404, { error: 'item non trovato' }.to_json unless item

  item = DB.get_first_row("SELECT id, nome, topic_id FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  DataManager.undo_delete_item(item_id)

  if gruppo_id != 0 && item
    nome_utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [item['creato_da']]) || 'Utente'
    notifica_gruppo(gruppo_id, item['topic_id'], DataManager.build_item_action_message(nome_utente, item['nome'], 'rimesso_in_lista'))
  end

  { ok: true, restored: true }.to_json
end

patch '/lista/:id/disponibile' do
  item_id = params[:id].to_i
  body = json_body
  gruppo_id = body['gruppo_id']&.to_i
  user_id = body['user_id']&.to_i || 0
  disponibile = body['disponibile']

  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id
  halt 400, { error: 'stato mancante' }.to_json if disponibile.nil?

  item = DB.get_first_row("SELECT id, nome, topic_id, gruppo_id FROM items WHERE id = ? AND gruppo_id = ?", [item_id, gruppo_id])
  halt 404, { error: 'item non trovato' }.to_json unless item

  value = (disponibile == true || disponibile == 1 || disponibile.to_s == 'true')
  DataManager.set_disponibile(item_id, value)

  if gruppo_id != 0 && user_id != 0
    nome_utente = DB.get_first_value("SELECT first_name FROM user_names WHERE user_id = ?", [user_id]) || 'Utente'
    notifica_gruppo(gruppo_id, item['topic_id'], DataManager.build_item_action_message(nome_utente, item['nome'], value ? 'disponibile' : 'non_disponibile'))
  end

  { ok: true, disponibile: value }.to_json
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
  user_id = params[:user_id].to_i

  item_accessibile!(item_id, user_id)

  image_data = params[:file] ? params[:file][:tempfile].read : request.body.read
  halt 400, { error: 'nessun file ricevuto' }.to_json if image_data.nil? || image_data.empty?

  token = telegram_token_attivo
  halt 503, { error: 'Token bot non configurato' }.to_json unless token

  messaggio = nil
  begin
    upload = Faraday::UploadIO.new(StringIO.new(image_data), 'image/jpeg', 'foto.jpg')
    bot = Telegram::Bot::Client.new(token)
    messaggio = bot.api.send_photo(
      chat_id: user_id,
      photo: upload,
      disable_notification: true
    )
    foto = messaggio.photo&.last
    halt 502, { error: 'Telegram non ha restituito i dati della foto' }.to_json unless foto
  rescue Telegram::Bot::Exceptions::ResponseError => e
    halt 502, { error: "Upload Telegram fallito: #{e.message}" }.to_json
  ensure
    if messaggio
      bot.api.delete_message(chat_id: user_id, message_id: messaggio.message_id) rescue nil
    end
  end

  cache_dir = File.join(File.dirname(__FILE__), 'data', 'foto_cache')
  FileUtils.mkdir_p(cache_dir)
  File.binwrite(File.join(cache_dir, "#{foto.file_unique_id}.jpg"), image_data)

  DB.execute(
    "INSERT INTO item_images (item_id, file_id, file_unique_id) VALUES (?, ?, ?)",
    [item_id, foto.file_id, foto.file_unique_id]
  )
  status 201
  { ok: true }.to_json
end

delete '/lista/:item_id/foto' do
  item_id = params[:item_id].to_i
  user_id = params[:user_id]&.to_i || 0
  item_accessibile!(item_id, user_id)

  immagini = Lista.rimuovi_immagine(item_id)
  cache_dir = File.join(File.dirname(__FILE__), 'data', 'foto_cache')
  immagini.each do |immagine|
    unique_id = immagine['file_unique_id'].to_s
    FileUtils.rm_f(File.join(cache_dir, "#{unique_id}.jpg")) unless unique_id.empty?
  end

  { ok: true, rimosse: immagini.size }.to_json
end

# Dati utente per il collegamento app (esentato da auth: usato anche per recupero nome)
get '/me' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  row = DB.get_first_row(
    "SELECT first_name, last_name FROM user_names WHERE user_id = ?", [user_id]
  )
  halt 404, { error: 'utente non trovato' }.to_json unless row
  {
    first_name: row['first_name'].to_s,
    last_name:  row['last_name'].to_s,
    is_creator: Whitelist.is_creator?(user_id)
  }.to_json
end

# --- Helper admin: verifica che il chiamante sia il Creatore ---
def richiedi_creator!(user_id)
  halt 403, { error: 'Solo il Creatore può eseguire questa operazione' }.to_json unless Whitelist.is_creator?(user_id)
end

# Lista richieste di accesso in sospeso
get '/admin/pending' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  richiedi_creator!(user_id)
  rows = Whitelist.get_pending_requests
  rows.map { |r| { user_id: r['user_id'], username: r['username'].to_s, full_name: r['full_name'].to_s, requested_at: r['requested_at'].to_s } }.to_json
end

# Approva una richiesta di accesso
post '/admin/pending/:target_id/approva' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  richiedi_creator!(user_id)
  target_id = params[:target_id].to_i
  pending = Whitelist.get_pending_requests.find { |r| r['user_id'] == target_id }
  halt 404, { error: 'Richiesta non trovata' }.to_json unless pending
  Whitelist.approve_user(target_id, pending['username'].to_s, pending['full_name'].to_s)
  { ok: true, user_id: target_id }.to_json
end

# Rifiuta (elimina) una richiesta di accesso
delete '/admin/pending/:target_id' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  richiedi_creator!(user_id)
  Whitelist.remove_pending_request(params[:target_id].to_i)
  { ok: true }.to_json
end

# Lista utenti autorizzati
get '/admin/utenti' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  richiedi_creator!(user_id)
  rows = Whitelist.all_users
  creator_id = Whitelist.get_creator_id
  rows.map { |r| { user_id: r['user_id'], username: r['username'].to_s, full_name: r['full_name'].to_s, added_at: r['added_at'].to_s, is_creator: r['user_id'] == creator_id } }.to_json
end

# Revoca accesso a un utente (il Creatore non può revocare se stesso)
delete '/admin/utenti/:target_id' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0
  richiedi_creator!(user_id)
  target_id = params[:target_id].to_i
  halt 400, { error: 'Il Creatore non può revocare se stesso' }.to_json if target_id == user_id
  DB.execute("DELETE FROM whitelist WHERE user_id = ?", [target_id])
  { ok: true, user_id: target_id }.to_json
end

# Helper condiviso per serializzare un item verso l'app Android
def serializza_item(i, nome_gruppo: '')
  # Combina gruppo e topic in un'unica etichetta
  t_nome = i['nome_topic'].to_s.strip
  gruppo_label = nome_gruppo.empty? ? '' : (t_nome.empty? ? nome_gruppo : "#{nome_gruppo} \u2022 #{t_nome}")
  categoria_id = i['categoria_id']
  categoria_nome = i['categoria_nome'].to_s.strip
  {
    id:            i['id'],
    gruppo_id:     i['gruppo_id'],
    topic_id:      i['topic_id'],
    nome_topic:    i['nome_topic'].to_s,
    nome:          i['nome'],
    link_url:      i['link_url'].to_s,
    categoria_id:  categoria_id.nil? ? nil : categoria_id.to_i,
    categoria_nome: categoria_nome,
    comprato:      i['comprato'].to_s.empty? ? '' : i['buyer_initials'].to_s,
    buyer_initials: i['buyer_initials'].to_s,
    creato_da:     i['creato_da'],
    user_initials: i['user_initials'].to_s,
    creato_il:     i['creato_il'],
    deleted:       i['deleted'].to_i == 1,
    disponibile:   i['disponibile'].to_i != 0,
    has_foto:      i['ha_foto'].to_i > 0,
    nome_gruppo:   gruppo_label,
    nome_contesto: gruppo_label.empty? ? 'Lista Personale' : gruppo_label
  }
end

# Conteggi leggeri per le voci trasversali del menu Android.
get '/lista/conteggi' do
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0

  miei = DB.get_first_value(<<~SQL, [user_id, user_id]).to_i
    SELECT COUNT(*) FROM items i
    WHERE i.creato_da = ?
      AND (i.gruppo_id = 0 OR i.gruppo_id IN (
        SELECT gruppo_id FROM memberships WHERE user_id = ?
      ))
  SQL
  tutti = DB.get_first_value(<<~SQL, [user_id, user_id]).to_i
    SELECT COUNT(*) FROM items i
    WHERE i.gruppo_id IN (SELECT gruppo_id FROM memberships WHERE user_id = ?)
       OR (i.gruppo_id = 0 AND i.creato_da = ?)
  SQL

  { tutti: tutti, miei: miei }.to_json
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
  user_id = params[:user_id]&.to_i
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  rows = if user_id && user_id != 0
    DB.execute(
      "SELECT c.id, c.nome, c.codice, c.formato, c.user_id,
              CASE WHEN c.user_id = ? THEN 1 ELSE 0 END AS mia,
              CASE WHEN g.carta_id IS NULL THEN 0 ELSE 1 END AS condivisa
       FROM carte_fedelta c
       LEFT JOIN gruppo_carte_collegamenti g
         ON g.carta_id = c.id AND g.gruppo_id = ?
       WHERE c.user_id = ? OR g.carta_id IS NOT NULL
       ORDER BY LOWER(c.nome)",
      [user_id, gruppo_id, user_id]
    )
  else
    DB.execute(
      "SELECT c.id, c.nome, c.codice, c.formato, c.user_id,
              0 AS mia,
              1 AS condivisa
       FROM carte_fedelta c
       JOIN gruppo_carte_collegamenti g ON c.id = g.carta_id
       WHERE g.gruppo_id = ?
       ORDER BY LOWER(c.nome)",
      [gruppo_id]
    )
  end

  rows.map { |r|
    {
      id: r['id'],
      nome: r['nome'],
      codice: r['codice'],
      formato: r['formato'].to_s,
      mia: r['mia'].to_i == 1,
      condivisa: r['condivisa'].to_i == 1,
      owner_id: r['user_id']
    }
  }.to_json
end

# Le mie carte con flag condivisa per un gruppo (gruppo_id=0 → solo lista)
get '/carte/mie' do
  user_id   = params[:user_id]&.to_i
  gruppo_id = params[:gruppo_id]&.to_i || 0
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0

  rows = DB.execute(
    "SELECT c.id, c.nome, c.codice, c.formato, c.user_id,
       (SELECT 1 FROM gruppo_carte_collegamenti g WHERE g.carta_id = c.id AND g.gruppo_id = ?) AS condivisa
     FROM carte_fedelta c WHERE c.user_id = ? ORDER BY LOWER(c.nome) ASC",
    [gruppo_id, user_id]
  )
  rows.map { |r|
    { id: r['id'], nome: r['nome'], codice: r['codice'],
      formato: r['formato'].to_s,
      condivisa: !r['condivisa'].nil?,
      mia: true,
      owner_id: r['user_id'] }
  }.to_json
end

# Legge il barcode da un'immagine multipart; l'immagine viene eliminata dopo la scansione
post '/carte/scan' do
  img = params[:immagine]
  halt 400, { error: 'immagine mancante' }.to_json unless img

  dir = File.join(File.dirname(__FILE__), 'data', 'carte')
  FileUtils.mkdir_p(dir)
  ext      = File.extname(img[:filename].to_s.downcase)
  ext      = '.jpg' if ext.empty?
  tmp_path = File.join(dir, "scan_#{SecureRandom.hex(8)}#{ext}")
  File.open(tmp_path, 'wb') { |f| f.write(img[:tempfile].read) }

  result = BarcodeScanner.scan_image(tmp_path)
  File.delete(tmp_path) rescue nil

  halt 404, { error: 'nessun codice trovato' }.to_json unless result
  { codice: result[:data], formato: result[:format] }.to_json
end

post '/carte' do
  body    = json_body
  user_id = body['user_id']&.to_i
  nome    = body['nome'].to_s.strip
  codice  = body['codice'].to_s.strip
  halt 400, { error: 'parametri mancanti' }.to_json if user_id.nil? || nome.empty? || codice.empty?

  formato = identifica_formato_codice(codice)
  DB.execute("INSERT INTO carte_fedelta (user_id, nome, codice, formato) VALUES (?, ?, ?, ?)",
             [user_id, nome, codice, formato])
  carta_id = DB.last_insert_row_id

  result = CarteFedelta.genera_barcode_con_nome(codice, nome, user_id, formato)
  if result && result[:img_path]
    DB.execute("UPDATE carte_fedelta SET immagine_path = ? WHERE id = ?", [result[:img_path], carta_id])
  end

  status 201
  { ok: true, id: carta_id, formato: formato }.to_json
end

delete '/carte/:id/collega' do
  carta_id  = params[:id].to_i
  gruppo_id = params[:gruppo_id]&.to_i
  halt 400, { error: 'gruppo_id mancante' }.to_json unless gruppo_id

  DB.execute("DELETE FROM gruppo_carte_collegamenti WHERE carta_id = ? AND gruppo_id = ?",
             [carta_id, gruppo_id])
  { ok: true }.to_json
end

post '/carte/:id/collega' do
  carta_id  = params[:id].to_i
  body      = json_body
  gruppo_id = body['gruppo_id']&.to_i
  user_id   = body['user_id']&.to_i
  halt 400, { error: 'parametri mancanti' }.to_json if gruppo_id.nil? || user_id.nil?

  halt 403, { error: 'non autorizzato' }.to_json unless DB.get_first_value(
    "SELECT id FROM carte_fedelta WHERE id = ? AND user_id = ?", [carta_id, user_id]
  )
  DB.execute("INSERT OR IGNORE INTO gruppo_carte_collegamenti (gruppo_id, carta_id, added_by) VALUES (?, ?, ?)",
             [gruppo_id, carta_id, user_id])
  { ok: true }.to_json
end

delete '/carte/:id' do
  carta_id = params[:id].to_i
  user_id  = params[:user_id]&.to_i
  halt 400, { error: 'user_id mancante' }.to_json unless user_id && user_id != 0

  DB.execute("DELETE FROM gruppo_carte_collegamenti WHERE carta_id = ?", [carta_id])
  DataManager.elimina_carta(carta_id, user_id)
  { ok: true }.to_json
end
