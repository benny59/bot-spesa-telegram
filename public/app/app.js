// PWA Bot Spesa - fase 1: login con PIN, gruppi/topic, lista, aggiunta, spunta.
// Nessuna build: modulo ES servito così com'è da api_server.rb (public/app).

const POLL_MS = 30000;
const INSTALL_SNOOZE_MS = 14 * 24 * 3600 * 1000;

const $ = (sel) => document.querySelector(sel);

const state = {
  auth: load('spesa.auth'),            // { token, userId, firstName }
  // vista: '' = lista del gruppo/topic, 'tutti' / 'miei' = viste trasversali.
  // gruppoId/topicId restano l'ultima lista aperta: lì vanno gli articoli aggiunti.
  sel: { vista: '', ...(load('spesa.sel') || { gruppoId: null, topicId: 0 }) },
  conteggi: { tutti: null, miei: null },
  gruppi: [],
  topics: {},                          // gruppoId -> [{ topic_id, nome }]
  items: [],
  categorie: [],
  pending: new Set(),                  // id articoli con chiamata in corso
  installPrompt: null
};

// ---------- utilità ----------

function load(key) {
  try { return JSON.parse(localStorage.getItem(key)); } catch { return null; }
}

function save(key, value) {
  localStorage.setItem(key, JSON.stringify(value));
}

function esc(text) {
  return String(text ?? '').replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

let toastTimer;
function toast(message) {
  const el = $('#toast');
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3000);
}

function initialsOf(name) {
  return (name || '?').trim().slice(0, 2).toUpperCase();
}

class AuthError extends Error {}

async function api(path, { method = 'GET', body, query } = {}) {
  const url = new URL(path, location.origin);
  Object.entries(query || {}).forEach(([k, v]) => url.searchParams.set(k, v));
  const headers = {};
  if (state.auth?.token) headers.Authorization = `Bearer ${state.auth.token}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const res = await fetch(url, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    cache: 'no-store'
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) throw new AuthError('Non autorizzato');
  if (!res.ok) throw new Error(data.error || `Errore ${res.status}`);
  return data;
}

// Upload foto: multipart, niente Content-Type manuale (lo imposta il browser col boundary).
async function apiUpload(path, { query, file } = {}) {
  const url = new URL(path, location.origin);
  Object.entries(query || {}).forEach(([k, v]) => url.searchParams.set(k, v));
  const headers = {};
  if (state.auth?.token) headers.Authorization = `Bearer ${state.auth.token}`;
  const form = new FormData();
  form.append('file', file, file.name || 'foto.jpg');

  const res = await fetch(url, { method: 'POST', headers, body: form, cache: 'no-store' });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401) throw new AuthError('Non autorizzato');
  if (!res.ok) throw new Error(data.error || `Errore ${res.status}`);
  return data;
}

// Le foto richiedono il bearer token: niente <img src> diretto, si scarica come blob.
async function fetchFotoBlobUrl(itemId) {
  const headers = {};
  if (state.auth?.token) headers.Authorization = `Bearer ${state.auth.token}`;
  const res = await fetch(`/foto/${itemId}`, { headers, cache: 'no-store' });
  if (res.status === 401) throw new AuthError('Non autorizzato');
  if (!res.ok) return null;
  return URL.createObjectURL(await res.blob());
}

function handleError(err) {
  if (err instanceof AuthError) {
    logout();
    return;
  }
  toast(navigator.onLine ? err.message : 'Sei offline');
}

// ---------- login ----------

function showLogin() {
  if ($('#dlg-login').open) return;
  $('#login-error').hidden = true;
  $('#login-pin').value = '';
  $('#dlg-login').showModal();
}

$('#dlg-login').addEventListener('cancel', (e) => e.preventDefault()); // non chiudibile con Esc

$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const pin = $('#login-pin').value.trim();
  const errEl = $('#login-error');
  errEl.hidden = true;
  try {
    const res = await api('/collega', { method: 'POST', body: { pin } });
    state.auth = { token: res.api_token || '', userId: res.user_id, firstName: res.first_name || '' };
    save('spesa.auth', state.auth);
    $('#dlg-login').close();
    await start();
  } catch (err) {
    errEl.textContent = err.message;
    errEl.hidden = false;
  }
});

function logout() {
  localStorage.removeItem('spesa.auth');
  localStorage.removeItem('spesa.sel');
  state.auth = null;
  state.sel = { vista: '', gruppoId: null, topicId: 0 };
  state.items = [];
  localStorage.removeItem('spesa.preferiti');
  setHelperOpen(false);
  render();
  showLogin();
}

// ---------- gruppi e topic ----------

const VISTE = { tutti: 'Tutti gli articoli', miei: 'I miei articoli' };
const PALETTE = ['#1976D2', '#2E7D32', '#00695C', '#E65100', '#C62828', '#6A1B9A', '#283593', '#4E342E'];

function contextColor(gruppoId, topicId) {
  if (!gruppoId) return '#455A64'; // Lista Personale, come nell'app Android
  return PALETTE[Math.abs(gruppoId * 31 + topicId) % PALETTE.length];
}

async function loadGruppi() {
  state.gruppi = await api('/gruppi', { query: { user_id: state.auth.userId } });
  save('spesa.gruppi', state.gruppi);
  const entries = await Promise.all(state.gruppi.map(async (g) => {
    const topics = await api('/topics', { query: { gruppo_id: g.id } }).catch(() => []);
    return [g.id, topics];
  }));
  state.topics = Object.fromEntries(entries);
  save('spesa.topics', state.topics);

  const valid = state.gruppi.some((g) => g.id === state.sel.gruppoId);
  if (!valid) {
    // di default il primo gruppo reale, altrimenti la Lista Personale
    const first = state.gruppi.find((g) => g.id !== 0) || state.gruppi[0];
    state.sel = { ...state.sel, gruppoId: first ? first.id : 0, topicId: 0 };
    save('spesa.sel', state.sel);
  }
}

function currentGruppo() {
  return state.gruppi.find((g) => g.id === state.sel.gruppoId);
}

function currentTopic() {
  return (state.topics[state.sel.gruppoId] || []).find((t) => t.topic_id === state.sel.topicId);
}

function selectContext(gruppoId, topicId, reload = true) {
  state.sel = { vista: '', gruppoId, topicId };
  save('spesa.sel', state.sel);
  document.body.classList.remove('nav-open');
  $('#nav-backdrop').hidden = true;
  state.items = load(cacheKey()) || [];
  render();
  if (reload) {
    refreshLista();
    loadCategorie();
    if (helper.open) loadHelper();
  }
}

function selectVista(vista) {
  state.sel = { ...state.sel, vista };
  save('spesa.sel', state.sel);
  toggleNav(false);
  state.items = load(cacheKey()) || [];
  render();
  refreshLista();
}

function renderNav() {
  $('#nav-user').textContent = state.auth ? `Collegato come ${state.auth.firstName}` : '';
  const viste = Object.entries(VISTE).map(([key, label]) => {
    const n = state.conteggi[key];
    const count = n === null || n === undefined ? '' : `<span class="count">${n}</span>`;
    return `<li><button class="${state.sel.vista === key ? 'active' : ''}" data-vista="${key}">${label}${count}</button></li>`;
  }).join('');
  $('#nav-list').innerHTML = `<li><div class="gruppo">Viste</div><ul>${viste}</ul></li>` + state.gruppi.map((g) => {
    const topics = state.topics[g.id] || [{ topic_id: 0, nome: 'Principale' }];
    const buttons = topics.map((t) => {
      const active = !state.sel.vista && g.id === state.sel.gruppoId && t.topic_id === state.sel.topicId;
      return `<li><button class="${active ? 'active' : ''}" data-gruppo="${g.id}" data-topic="${t.topic_id}">${esc(t.nome)}</button></li>`;
    }).join('');
    return `<li><div class="gruppo">${esc(g.nome)}</div><ul>${buttons}</ul></li>`;
  }).join('');
}

$('#nav-list').addEventListener('click', (e) => {
  const vista = e.target.closest('button[data-vista]');
  if (vista) return selectVista(vista.dataset.vista);
  const btn = e.target.closest('button[data-gruppo]');
  if (btn) selectContext(Number(btn.dataset.gruppo), Number(btn.dataset.topic));
});

function toggleNav(open) {
  document.body.classList.toggle('nav-open', open);
  $('#nav-backdrop').hidden = !open;
}
$('#btn-nav').addEventListener('click', () => toggleNav(true));
$('#nav-backdrop').addEventListener('click', () => toggleNav(false));

// ---------- lista ----------

function cacheKey() {
  if (state.sel.vista) return `spesa.lista.${state.sel.vista}`;
  return `spesa.lista.${state.sel.gruppoId}.${state.sel.topicId}`;
}

let refreshing = null;
let refreshAgain = false;
// Un solo refresh alla volta; se ne arriva un altro durante il volo (es. dopo una modifica)
// viene ripetuto alla fine, così il risultato non è mai precedente alla modifica.
async function refreshLista() {
  if (!state.auth || state.sel.gruppoId === null) return;
  if (refreshing) {
    refreshAgain = true;
    return refreshing;
  }
  refreshing = doRefresh();
  try {
    await refreshing;
  } finally {
    refreshing = null;
  }
  if (refreshAgain) {
    refreshAgain = false;
    await refreshLista();
  }
}

async function doRefresh() {
  const sel = { ...state.sel };
  const user = state.auth.userId;
  try {
    const items = sel.vista
      ? await api(`/lista/${sel.vista}`, { query: { user_id: user } })
      : await api('/lista', { query: { gruppo_id: sel.gruppoId, topic_id: sel.topicId, user_id: user } });
    loadConteggi();
    if (sel.vista !== state.sel.vista || sel.gruppoId !== state.sel.gruppoId ||
        sel.topicId !== state.sel.topicId) return; // cambiato nel frattempo
    state.items = items;
    save(cacheKey(), items);
    save(`${cacheKey()}.at`, Date.now());
    $('#offline').hidden = true;
    renderLista();
  } catch (err) {
    if (err instanceof AuthError) return handleError(err);
    const at = load(`${cacheKey()}.at`);
    $('#offline').textContent = at
      ? `Server non raggiungibile: lista aggiornata alle ${new Date(at).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' })}`
      : 'Server non raggiungibile';
    $('#offline').hidden = false;
  }
}

async function loadConteggi() {
  try {
    const conteggi = await api('/lista/conteggi', { query: { user_id: state.auth.userId } });
    if (conteggi.tutti === state.conteggi.tutti && conteggi.miei === state.conteggi.miei) return;
    state.conteggi = conteggi;
    renderNav();
  } catch {
    // i conteggi sono solo informativi
  }
}

function categoriaLabel(item) {
  const nome = item.categoria_nome || '';
  const effimera = !item.categoria_id && nome;
  return effimera ? nome.toLowerCase() : nome;
}

function sectionLabel(item) {
  if (item.deleted) return 'Cancellati';
  if (item.comprato) return 'Nel carrello';
  if (!item.disponibile) return 'Non disponibili';
  return categoriaLabel(item) || 'Senza categoria';
}

function itemClass(item) {
  if (item.deleted) return 'deleted';
  if (!item.disponibile) return 'unavailable';
  if (item.comprato) return 'bought';
  return '';
}

function renderItem(item) {
  const cls = itemClass(item);
  const mark = { deleted: '↺', unavailable: '✕', bought: '✓' }[cls] || '';
  const sameUser = item.user_initials === item.buyer_initials;
  const showCreator = cls !== 'bought' || !sameUser;
  const creator = showCreator ? `<span class="initials">${esc(item.user_initials || '?')}</span>` : '';
  const buyer = cls === 'bought'
    ? `<span class="initials buyer">${esc(item.buyer_initials || item.comprato)}</span>`
    : '';
  // nelle viste trasversali la sezione è il gruppo/topic: la categoria va sulla riga
  const categoria = state.sel.vista && categoriaLabel(item)
    ? `<div class="item-cat">${item.categoria_id ? '▣' : '◌'} ${esc(categoriaLabel(item))}</div>`
    : '';

  return `<li class="item ${cls} ${state.pending.has(item.id) ? 'pending' : ''}" data-id="${item.id}">
    <button class="item-main" data-action="tap">
      ${creator}
      <span class="item-text"><div class="item-nome">${esc(item.nome)}</div>${categoria}</span>
      <span class="mark">${mark}</span>
      ${buyer}
    </button>
    ${item.has_foto ? '<button class="icon-btn item-foto" data-action="foto" aria-label="Foto">🖼️</button>' : ''}
    <button class="icon-btn item-more" data-action="more" aria-label="Azioni">⋯</button>
  </li>`;
}

function renderLista() {
  let html = '';
  let lastSection = null;
  for (const item of state.items) {
    if (state.sel.vista) {
      const section = `${item.gruppo_id}.${item.topic_id}`;
      if (section !== lastSection) {
        const color = contextColor(item.gruppo_id, item.topic_id);
        html += `<li><button class="context" style="background:${color}" data-gruppo="${item.gruppo_id}" data-topic="${item.topic_id}">▸ ${esc(item.nome_contesto)}</button></li>`;
        lastSection = section;
      }
    } else {
      const section = sectionLabel(item);
      if (section !== lastSection) {
        html += `<li class="section">${esc(section)}</li>`;
        lastSection = section;
      }
    }
    html += renderItem(item);
  }
  $('#lista').innerHTML = html;
  $('#empty').hidden = state.items.length > 0 || !state.auth;
}

// Lista in cui finiscono gli articoli aggiunti (anche dalle viste Tutti / Miei)
function destinazioneLabel() {
  const gruppo = currentGruppo();
  const topic = currentTopic();
  if (!gruppo) return '';
  return `${gruppo.nome}${gruppo.id !== 0 && topic ? ` • ${topic.nome}` : ''}`;
}

function render() {
  const gruppo = currentGruppo();
  const topic = currentTopic();
  const destinazione = destinazioneLabel();
  if (state.sel.vista) {
    $('#title-main').textContent = VISTE[state.sel.vista];
    $('#title-sub').textContent = '';
    $('#add-input').placeholder = destinazione ? `Aggiungi a ${destinazione}…` : 'Aggiungi…';
  } else {
    $('#title-main').textContent = gruppo ? gruppo.nome : 'Spesa';
    $('#title-sub').textContent = gruppo && gruppo.id !== 0 && topic ? topic.nome : '';
    $('#add-input').placeholder = 'Aggiungi… (più articoli separati da virgola)';
  }
  renderNav();
  renderLista();
}

function findItem(id) {
  return state.items.find((i) => i.id === id);
}

async function runOnItem(item, request) {
  state.pending.add(item.id);
  renderLista();
  try {
    await request();
  } catch (err) {
    handleError(err);
  } finally {
    state.pending.delete(item.id);
    await refreshLista();
    renderLista();
  }
}

function tapItem(item) {
  const user = state.auth.userId;
  if (item.deleted) {
    return runOnItem(item, () => api(`/lista/${item.id}/restore`, {
      method: 'POST', query: { gruppo_id: item.gruppo_id, user_id: user }
    }));
  }
  if (!item.disponibile) {
    return runOnItem(item, () => api(`/lista/${item.id}/disponibile`, {
      method: 'PATCH', body: { gruppo_id: item.gruppo_id, user_id: user, disponibile: true }
    }));
  }
  // spunta ottimistica: il risultato vero arriva dal refresh
  item.comprato = item.comprato ? '' : initialsOf(state.auth.firstName);
  item.buyer_initials = item.comprato;
  return runOnItem(item, () => api(`/lista/${item.id}/toggle`, {
    method: 'PATCH', body: { gruppo_id: item.gruppo_id, user_id: user }
  }));
}

let menuItem = null;
function openItemMenu(item) {
  menuItem = item;
  $('#item-title').textContent = item.nome;
  $('#item-foto').textContent = item.has_foto ? '🖼️ Vedi/cambia foto' : '📷 Aggiungi foto';
  $('#item-disponibile').textContent = item.disponibile ? '🚫 Segna non disponibile' : '✅ Segna disponibile';
  $('#item-delete').textContent = item.deleted ? '↺ Rimetti in lista' : '🗑️ Elimina';
  $('#dlg-item').showModal();
}

$('#dlg-item').addEventListener('close', () => {
  const action = $('#dlg-item').returnValue;
  const item = menuItem;
  $('#dlg-item').returnValue = '';
  if (!item || !action) return;
  const user = state.auth.userId;

  if (action === 'rename') {
    const nome = prompt('Nuovo nome', item.nome);
    if (!nome || !nome.trim() || nome.trim() === item.nome) return;
    runOnItem(item, () => api(`/lista/${item.id}`, { method: 'PATCH', body: { nome: nome.trim(), user_id: user } }));
  } else if (action === 'foto') {
    openFotoDialog(item);
  } else if (action === 'disponibile') {
    runOnItem(item, () => api(`/lista/${item.id}/disponibile`, {
      method: 'PATCH', body: { gruppo_id: item.gruppo_id, user_id: user, disponibile: !item.disponibile }
    }));
  } else if (action === 'delete') {
    const path = item.deleted ? `/lista/${item.id}/restore` : `/lista/${item.id}`;
    runOnItem(item, () => api(path, {
      method: item.deleted ? 'POST' : 'DELETE', query: { gruppo_id: item.gruppo_id, user_id: user }
    }));
  }
});

$('#lista').addEventListener('click', (e) => {
  const context = e.target.closest('button.context');
  if (context) return selectContext(Number(context.dataset.gruppo), Number(context.dataset.topic));
  const btn = e.target.closest('button[data-action]');
  const li = e.target.closest('.item');
  if (!btn || !li) return;
  const item = findItem(Number(li.dataset.id));
  if (!item || state.pending.has(item.id)) return;
  if (btn.dataset.action === 'tap') tapItem(item);
  else if (btn.dataset.action === 'foto') openFotoDialog(item);
  else openItemMenu(item);
});

// ---------- foto articolo: carica da file, trascina o incolla ----------

let fotoItem = null;
let fotoBlobUrl = null;

function resetFotoPreview() {
  if (fotoBlobUrl) { URL.revokeObjectURL(fotoBlobUrl); fotoBlobUrl = null; }
  $('#foto-img').hidden = true;
  $('#foto-img').src = '';
}

async function openFotoDialog(item) {
  fotoItem = item;
  resetFotoPreview();
  $('#foto-title').textContent = item.nome;
  $('#foto-delete').hidden = !item.has_foto;
  $('#foto-loading').hidden = !item.has_foto;
  $('#dlg-foto').showModal();
  if (item.has_foto) await showFotoPreview(item.id);
}

async function showFotoPreview(itemId) {
  $('#foto-loading').hidden = false;
  try {
    const url = await fetchFotoBlobUrl(itemId);
    if (!fotoItem || fotoItem.id !== itemId) return; // dialog chiuso o cambiato nel frattempo
    if (url) {
      fotoBlobUrl = url;
      $('#foto-img').src = url;
      $('#foto-img').hidden = false;
    }
  } catch (err) {
    handleError(err);
  } finally {
    $('#foto-loading').hidden = true;
  }
}

async function uploadFoto(file) {
  if (!fotoItem || !file.type.startsWith('image/')) return;
  const item = fotoItem;
  $('#foto-loading').hidden = false;
  try {
    await apiUpload(`/lista/${item.id}/foto`, { query: { user_id: state.auth.userId }, file });
    item.has_foto = true;
    resetFotoPreview();
    await showFotoPreview(item.id);
    $('#foto-delete').hidden = false;
    toast('📷 Foto salvata');
    refreshLista();
  } catch (err) {
    $('#foto-loading').hidden = true;
    handleError(err);
  }
}

$('#foto-input').addEventListener('change', () => {
  const file = $('#foto-input').files[0];
  $('#foto-input').value = '';
  if (file) uploadFoto(file);
});

const fotoDrop = $('#foto-drop');
['dragenter', 'dragover'].forEach((ev) => fotoDrop.addEventListener(ev, (e) => {
  e.preventDefault();
  fotoDrop.classList.add('drag');
}));
['dragleave', 'drop'].forEach((ev) => fotoDrop.addEventListener(ev, (e) => {
  e.preventDefault();
  fotoDrop.classList.remove('drag');
}));
fotoDrop.addEventListener('drop', (e) => {
  const file = [...(e.dataTransfer?.files || [])].find((f) => f.type.startsWith('image/'));
  if (file) uploadFoto(file);
});

// incolla con Ctrl+V mentre il dialog foto è aperto
document.addEventListener('paste', (e) => {
  if (!$('#dlg-foto').open || !fotoItem) return;
  const item = [...(e.clipboardData?.items || [])].find((i) => i.type.startsWith('image/'));
  if (!item) return;
  e.preventDefault();
  const file = item.getAsFile();
  if (file) uploadFoto(file);
});

$('#foto-delete').addEventListener('click', async () => {
  if (!fotoItem || !confirm('Rimuovere la foto?')) return;
  try {
    await api(`/lista/${fotoItem.id}/foto`, { method: 'DELETE', query: { user_id: state.auth.userId } });
    fotoItem.has_foto = false;
    resetFotoPreview();
    $('#foto-delete').hidden = true;
    toast('🗑️ Foto rimossa');
    refreshLista();
  } catch (err) {
    handleError(err);
  }
});

$('#foto-close').addEventListener('click', () => $('#dlg-foto').close());
$('#dlg-foto').addEventListener('close', () => {
  resetFotoPreview();
  fotoItem = null;
});

// ---------- carte fedeltà: sola lettura (gestione da Telegram o app Android) ----------

let carteDisponibili = [];
let cartaBlobUrl = null;

async function fetchCartaBlobUrl(cartaId) {
  const headers = {};
  if (state.auth?.token) headers.Authorization = `Bearer ${state.auth.token}`;
  const res = await fetch(`/carte/${cartaId}/immagine?user_id=${state.auth.userId}`, { headers, cache: 'no-store' });
  if (res.status === 401) throw new AuthError('Non autorizzato');
  if (!res.ok) return null;
  return URL.createObjectURL(await res.blob());
}

function cartaMarker(carta) {
  if (carta.mia && carta.condivisa) return '🟢';
  if (carta.mia) return '🟡';
  return '🔵';
}

async function openCarteDialog() {
  $('#carte-list').innerHTML = '';
  $('#carte-empty').hidden = true;
  $('#dlg-carte').showModal();
  try {
    carteDisponibili = await api('/carte/disponibili', { query: { user_id: state.auth.userId } });
    $('#carte-empty').hidden = carteDisponibili.length > 0;
    $('#carte-list').innerHTML = carteDisponibili.map((c) => (
      `<li><button data-id="${c.id}">
        <span>${cartaMarker(c)}</span>
        <span class="grow">${esc(c.nome)}</span>
      </button></li>`
    )).join('');
  } catch (err) {
    $('#dlg-carte').close();
    handleError(err);
  }
}

$('#carte-close').addEventListener('click', () => $('#dlg-carte').close());

$('#carte-list').addEventListener('click', (e) => {
  const btn = e.target.closest('button[data-id]');
  if (!btn) return;
  const carta = carteDisponibili.find((c) => c.id === Number(btn.dataset.id));
  if (carta) openCartaDialog(carta);
});

function resetCartaPreview() {
  if (cartaBlobUrl) { URL.revokeObjectURL(cartaBlobUrl); cartaBlobUrl = null; }
  $('#carta-img').hidden = true;
  $('#carta-img').src = '';
}

async function openCartaDialog(carta) {
  $('#dlg-carte').close();
  resetCartaPreview();
  $('#carta-nome').textContent = carta.nome;
  $('#carta-codice').textContent = carta.codice || '';
  $('#carta-loading').hidden = false;
  $('#dlg-carta').showModal();
  try {
    const url = await fetchCartaBlobUrl(carta.id);
    if (url) {
      cartaBlobUrl = url;
      $('#carta-img').src = url;
      $('#carta-img').hidden = false;
    }
  } catch (err) {
    handleError(err);
  } finally {
    $('#carta-loading').hidden = true;
  }
}

$('#carta-close').addEventListener('click', () => $('#dlg-carta').close());
$('#dlg-carta').addEventListener('close', resetCartaPreview);

// ---------- aggiunta ----------

async function loadCategorie() {
  const sel = { ...state.sel };
  try {
    const categorie = await api('/categorie', {
      query: { gruppo_id: sel.gruppoId, topic_id: sel.topicId, user_id: state.auth.userId }
    });
    if (sel.gruppoId !== state.sel.gruppoId || sel.topicId !== state.sel.topicId) return;
    state.categorie = categorie.sort((a, b) => a.nome.localeCompare(b.nome, 'it'));
  } catch {
    state.categorie = [];
  }
  $('#add-categoria').innerHTML = '<option value="">Categoria</option>' +
    state.categorie.map((c) => (
      c.effimera
        ? `<option value="e:${esc(c.nome)}">◌ ${esc(c.nome.toLowerCase())}</option>`
        : `<option value="${c.id}">${esc(c.nome)}</option>`
    )).join('');
}

$('#add-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const input = $('#add-input');
  let nome = input.value.trim();
  if (!nome || !state.auth || state.sel.gruppoId === null) return;

  const categoria = $('#add-categoria').value;
  const body = {
    gruppo_id: state.sel.gruppoId,
    topic_id: state.sel.topicId,
    user_id: state.auth.userId,
    split_items: true
  };
  if (categoria.startsWith('e:')) {
    // categoria effimera: sintassi "a, b & categoria" usata anche dal bot
    nome = `${nome} & ${categoria.slice(2)}`;
  } else if (categoria) {
    body.categoria_id = Number(categoria);
  }
  body.nome = nome;

  input.disabled = true;
  try {
    await api('/lista', { method: 'POST', body });
    input.value = '';
    $('#add-categoria').value = '';
    await refreshLista();
  } catch (err) {
    handleError(err);
  } finally {
    input.disabled = false;
    input.focus();
  }
});

// ---------- aiuto compilazione: suggeriti, storico, preferiti ----------
// Suggeriti (checklist) e storico condividono riga e toggle (POST /checklist/toggle).
// I preferiti sono in sola lettura: arrivano dall'ultimo backup fatto dall'app Android.

const helper = {
  open: false,
  tab: load('spesa.helperTab') || 'checklist',
  rows: [],              // righe normalizzate della scheda attiva
  pending: new Set(),
  note: ''
};

function formatData(value) {
  const m = /^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/.exec(value || '');
  return m ? `${m[3]}/${m[2]}/${m[1]} ${m[4]}:${m[5]}` : (value || '');
}

function categoriaRow(nome, effimera) {
  if (!nome) return 'Senza categoria';
  return `${effimera ? '◌' : '▣'} ${effimera ? nome.toLowerCase() : nome}`;
}

// articoli ancora da comprare nella lista di destinazione (per i preferiti)
async function itemsDestinazione() {
  if (!state.sel.vista) return state.items;
  return api('/lista', {
    query: { gruppo_id: state.sel.gruppoId, topic_id: state.sel.topicId, user_id: state.auth.userId }
  });
}

function storicoMeta(a) {
  const parts = [formatData(a.updated_at)];
  if (a.creatore) parts.push(`↳ ${a.creatore}`);
  if (a.acquirente) parts.push(`↗ ${a.acquirente}`);
  parts.push(`${a.conteggio} volte`);
  return parts.join(' · ');
}

async function fetchHelperRows(tab) {
  const dest = { gruppo_id: state.sel.gruppoId, topic_id: state.sel.topicId };
  if (tab === 'checklist') {
    const items = await api('/checklist', { query: { ...dest, user_id: state.auth.userId } });
    return {
      rows: items.map((i) => ({
        key: `c${i.id}`,
        nome: i.nome,
        label: i.nome_display || i.nome,
        meta: i.conteggio > 0 ? `acquistato ${i.conteggio}×` : '',
        section: categoriaRow(i.categoria_nome, i.categoria_effimera),
        inLista: i.in_lista,
        gtin: i.gtin
      }))
    };
  }
  if (tab === 'storico') {
    const acquisti = await api('/storico/acquisti', { query: { ...dest, limite: 50 } });
    return {
      rows: acquisti.map((a) => ({
        key: `s${a.id}`,
        nome: a.nome,
        label: a.nome_display || a.nome,
        meta: [a.categoria_nome ? categoriaRow(a.categoria_nome, a.categoria_effimera) : '', storicoMeta(a)]
          .filter(Boolean).join(' · '),
        inLista: a.in_lista,
        // come l'app Android: se ci sono più prodotti si usa il più recente
        gtin: a.prodotti?.[0]?.gtin || ''
      }))
    };
  }

  // preferiti: ultimo backup, ordinati per categoria come nell'app Android
  let backup;
  try {
    backup = await api('/utente/config/preferiti', { query: { user_id: state.auth.userId } });
    save('spesa.preferiti', backup);
  } catch (err) {
    if (err instanceof AuthError) throw err;
    backup = load('spesa.preferiti');
    if (!backup) {
      return { rows: [], note: 'Nessun backup dei preferiti: dall\'app Android apri Preferiti → Backup.' };
    }
  }
  const inLista = new Map((await itemsDestinazione())
    .filter((i) => !i.comprato && !i.deleted)
    .map((i) => [i.nome.trim().toLowerCase(), i.id]));
  const favorites = [...(backup.favorites || [])].sort((a, b) => (
    (!a.categoryName - !b.categoryName) ||
    (Number(a.categoryEphemeral) - Number(b.categoryEphemeral)) ||
    (a.categoryName || '').localeCompare(b.categoryName || '', 'it') ||
    a.description.localeCompare(b.description, 'it')
  ));
  return {
    note: `Backup dall'app Android del ${formatData((backup.lastBackupAt || '').replace('T', ' '))} · si modificano dall'app`,
    rows: favorites.map((f) => {
      const itemId = inLista.get(f.description.trim().toLowerCase());
      return {
        key: `p${f.id}`,
        nome: f.description,
        label: f.description,
        meta: '',
        section: categoriaRow(f.categoryName, f.categoryEphemeral),
        inLista: itemId !== undefined,
        itemId,
        favorite: f
      };
    })
  };
}

let helperLoad = 0;
async function loadHelper() {
  if (!state.auth || state.sel.gruppoId === null) return;
  const ticket = ++helperLoad;
  const tab = helper.tab;
  $('#helper-dest').textContent = `Aggiungi a: ${destinazioneLabel()}`;
  try {
    const { rows, note } = await fetchHelperRows(tab);
    if (ticket !== helperLoad) return; // nel frattempo è cambiata scheda o lista
    helper.rows = rows;
    helper.note = note || '';
  } catch (err) {
    if (ticket !== helperLoad) return;
    if (err instanceof AuthError) return handleError(err);
    helper.rows = [];
    helper.note = navigator.onLine ? `Errore: ${err.message}` : 'Sei offline';
  }
  renderHelper();
}

function renderHelper() {
  document.querySelectorAll('#helper .tabs button').forEach((b) => {
    b.classList.toggle('active', b.dataset.tab === helper.tab);
    b.setAttribute('aria-selected', b.dataset.tab === helper.tab);
  });
  $('#helper-note').textContent = helper.note;
  $('#helper-note').hidden = !helper.note;

  let html = '';
  let lastSection = null;
  for (const row of helper.rows) {
    if (row.section && row.section !== lastSection) {
      html += `<li class="section">${esc(row.section)}</li>`;
      lastSection = row.section;
    }
    const cls = `${row.inLista ? 'in-lista' : ''} ${helper.pending.has(row.key) ? 'pending' : ''}`;
    html += `<li><button class="sugg ${cls}" data-key="${esc(row.key)}">
      <span class="status">${row.inLista ? '✓' : '+'}</span>
      <span class="sugg-text">
        <div class="sugg-nome">${esc(row.label)}</div>
        ${row.meta ? `<div class="sugg-meta">${esc(row.meta)}</div>` : ''}
      </span>
    </button></li>`;
  }
  if (!helper.rows.length && !helper.note) html = '<li class="muted center">Nessun articolo</li>';
  $('#helper-list').innerHTML = html;
}

function toggleHelperRow(row) {
  const dest = { gruppo_id: state.sel.gruppoId, topic_id: state.sel.topicId };
  const user = state.auth.userId;
  if (!row.favorite) {
    return api('/checklist/toggle', {
      method: 'POST',
      body: { ...dest, user_id: user, nome: row.nome, in_lista: row.inLista, gtin: row.gtin || '' }
    });
  }
  if (row.inLista) {
    return api(`/lista/${row.itemId}/rimuovi`, { method: 'DELETE', query: { ...dest, user_id: user } });
  }
  const f = row.favorite;
  const body = { ...dest, user_id: user, nome: f.description, split_items: false };
  if (f.yukaLink) body.link_url = f.yukaLink;
  if (f.gtin) body.gtin = f.gtin;
  if (f.categoryId > 0) body.categoria_id = f.categoryId;
  if (f.telegramPhotoId && f.telegramPhotoFileName) {
    body.picture_id = f.telegramPhotoId;
    body.picture_file_name = f.telegramPhotoFileName;
  }
  return api('/lista', { method: 'POST', body });
}

$('#helper-list').addEventListener('click', async (e) => {
  const btn = e.target.closest('button.sugg');
  if (!btn) return;
  const row = helper.rows.find((r) => r.key === btn.dataset.key);
  if (!row || helper.pending.has(row.key)) return;
  helper.pending.add(row.key);
  renderHelper();
  try {
    await toggleHelperRow(row);
    await refreshLista(); // prima la lista: i preferiti la usano per lo stato ✓
  } catch (err) {
    handleError(err);
  } finally {
    helper.pending.delete(row.key);
    await loadHelper();
  }
});

function isWide() {
  return matchMedia('(min-width: 1200px)').matches;
}

function setHelperOpen(open) {
  helper.open = open;
  $('#helper').hidden = !open;
  $('#helper-backdrop').hidden = !open || isWide();
  document.body.classList.toggle('helper-open', open);
  save('spesa.helperOpen', open);
  if (open) loadHelper();
}

$('#btn-helper').addEventListener('click', () => setHelperOpen(!helper.open));
$('#helper-close').addEventListener('click', () => setHelperOpen(false));
$('#helper-backdrop').addEventListener('click', () => setHelperOpen(false));
document.querySelectorAll('#helper .tabs button').forEach((b) => b.addEventListener('click', () => {
  helper.tab = b.dataset.tab;
  save('spesa.helperTab', helper.tab);
  helper.rows = [];
  helper.note = '';
  renderHelper();
  loadHelper();
}));

// ---------- menu generale ----------

$('#btn-menu').addEventListener('click', () => {
  $('#menu-install').hidden = !state.installPrompt && !isIos();
  $('#menu-scopetta').textContent = state.sel.vista
    ? '🧹 Superscopetta (tutti i gruppi)'
    : '🧹 Scopetta (togli comprati e cancellati)';
  $('#dlg-menu').showModal();
});

$('#dlg-menu').addEventListener('close', async () => {
  const action = $('#dlg-menu').returnValue;
  $('#dlg-menu').returnValue = '';
  if (action === 'logout') {
    if (confirm('Scollegare questo dispositivo?')) logout();
  } else if (action === 'install') {
    doInstall();
  } else if (action === 'carte') {
    openCarteDialog();
  } else if (action === 'scopetta') {
    const daPulire = state.items.filter((i) => i.comprato || i.deleted).length;
    if (!daPulire) return toast('Nessun articolo comprato o cancellato');
    const ovunque = Boolean(state.sel.vista);
    const domanda = ovunque
      ? 'Superscopetta: rimuovere da tutti i gruppi gli articoli comprati o già cancellati?'
      : `Togliere dalla lista ${daPulire} articoli comprati o cancellati?`;
    if (!confirm(domanda)) return;
    try {
      if (ovunque) {
        await api('/lista/comprati/ovunque', { method: 'DELETE', query: { user_id: state.auth.userId } });
      } else {
        await api('/lista/comprati', {
          method: 'DELETE',
          query: { gruppo_id: state.sel.gruppoId, topic_id: state.sel.topicId, user_id: state.auth.userId }
        });
      }
      toast('🧹 Fatto');
      await refreshLista();
    } catch (err) {
      handleError(err);
    }
  }
});

$('#btn-refresh').addEventListener('click', async () => {
  await refreshLista();
  toast('Lista aggiornata');
});

// ---------- installazione ----------

function isStandalone() {
  return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
}

function isIos() {
  return /iphone|ipad|ipod/i.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

function maybeShowInstallBanner() {
  if (isStandalone()) return;
  const snoozed = load('spesa.installSnooze');
  if (snoozed && Date.now() - snoozed < INSTALL_SNOOZE_MS) return;
  if (!state.installPrompt && !isIos()) return;
  if (isIos()) {
    $('#install-text').textContent = 'Da Safari: Condividi → Aggiungi alla schermata Home.';
    $('#install-btn').textContent = 'Come fare';
  }
  $('#install-banner').hidden = false;
}

async function doInstall() {
  $('#install-banner').hidden = true;
  if (state.installPrompt) {
    state.installPrompt.prompt();
    await state.installPrompt.userChoice;
    state.installPrompt = null;
  } else if (isIos()) {
    $('#dlg-ios').showModal();
  }
}

window.addEventListener('beforeinstallprompt', (e) => {
  e.preventDefault();
  state.installPrompt = e;
  maybeShowInstallBanner();
});

window.addEventListener('appinstalled', () => {
  state.installPrompt = null;
  $('#install-banner').hidden = true;
});

$('#install-btn').addEventListener('click', doInstall);
$('#install-close').addEventListener('click', () => {
  save('spesa.installSnooze', Date.now());
  $('#install-banner').hidden = true;
});

// ---------- aggiornamento automatico e scorciatoie ----------

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') refreshLista();
});
window.addEventListener('online', refreshLista);
setInterval(() => {
  if (document.visibilityState === 'visible') refreshLista();
}, POLL_MS);

document.addEventListener('keydown', (e) => {
  const typing = ['INPUT', 'SELECT', 'TEXTAREA'].includes(document.activeElement?.tagName);
  if (typing || document.querySelector('dialog[open]')) return;
  if (e.key === '/' || e.key === 'n') {
    e.preventDefault();
    $('#add-input').focus();
  } else if (e.key === 'r') {
    refreshLista();
  } else if (e.key === 'c') {
    setHelperOpen(!helper.open);
  } else if (e.key === 'Escape') {
    toggleNav(false);
    if (!isWide()) setHelperOpen(false);
  }
});

// ---------- avvio ----------

async function start() {
  // mostra subito i dati in cache, poi aggiorna dalla rete
  state.gruppi = load('spesa.gruppi') || [];
  state.topics = load('spesa.topics') || {};
  state.items = load(cacheKey()) || [];
  render();
  try {
    await loadGruppi();
    render();
    await Promise.all([refreshLista(), loadCategorie()]);
    if (load('spesa.helperOpen') && isWide()) setHelperOpen(true);
  } catch (err) {
    if (err instanceof AuthError) return handleError(err);
    await refreshLista(); // mostra l'avviso offline
  }
}

if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}

if (state.auth) start();
else showLogin();
maybeShowInstallBanner();
