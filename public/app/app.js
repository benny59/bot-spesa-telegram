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

function render() {
  const gruppo = currentGruppo();
  const topic = currentTopic();
  const destinazione = gruppo ? `${gruppo.nome}${gruppo.id !== 0 && topic ? ` • ${topic.nome}` : ''}` : '';
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
  else openItemMenu(item);
});

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
  } else if (e.key === 'Escape') {
    toggleNav(false);
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
