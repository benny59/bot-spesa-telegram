"use strict";
const $ = id => document.getElementById(id);
function round2(x){ return Math.round(x*100)/100; }
function clone(o){ return JSON.parse(JSON.stringify(o)); }
function eur(x){ return x.toLocaleString("de-DE",{style:"currency",currency:"EUR"}); }
function pct(x,d=1){ if(!isFinite(x)) return "–"; const s = Math.abs(x).toFixed(d); return (x>0.00001?"+":x<-0.00001?"−":"")+s+" %"; }
function esc(s){ return String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c])); }
function d2(s){ const [y,m,d] = s.split("-").map(Number); return new Date(Date.UTC(y,m-1,d)); }
function days(a,b){ return Math.round((d2(b)-d2(a))/864e5); }
function fmtDay(s){ const d = d2(s); return d.getUTCDate()+" "+MONTHS_EN[d.getUTCMonth()]; }
function fmtMonth(ym){ const [y,m] = ym.split("-").map(Number); return MONTHS_EN[m-1]+" "+y; }
function cls(v){ return v>0.05?"up":v<-0.05?"down":""; }

function nomeVoce(it) { const n = (it.g || it.name || "").trim(); return n ? n.charAt(0).toUpperCase() + n.slice(1).toLowerCase() : ""; }

// Preferito di Spesa a cui corrisponde una riga (stesso nome generico), o null.
function favOf(it) {
  if (!it || !favs.length) return null;
  const g = String(it.g || "").trim().toLowerCase();
  return (g && favs.find(f => f.d.toLowerCase() === g)) || (typeof trovaPreferito === "function" ? trovaPreferito(it.name, favs) : null);
}
function favChip(it) { const f = favOf(it); return f ? `<span class="chip" title="${esc(f.e ? t("fav.badgeEan", {e: f.e}) : t("fav.badge"))}" style="color:var(--accent)">★ ${esc(t("fav.badge"))}${f.e ? " ⌗" : ""}</span>` : ""; }
// Codice a barre di un prodotto della libreria: campo "ean" (lo scrive anche "Add label"); "gtin" è il nome usato dalle prime scansioni.
function eanDi(l){ return String((l && (l.ean || l.gtin)) || ""); }
// Indice dei prodotti per codice: un EAN = un prodotto, le voci "negozio + descrizione" sono i suoi alias.
let eanCache = null;
function eanIndice(){
  if (eanCache && eanCache.v === memVer && eanCache.lib === library) return eanCache.map;
  const map = new Map();
  for (const l of Object.values(library)){ const e = eanDi(l); if (!e) continue; (map.get(e) || map.set(e, {ean: e, docs: []}).get(e)).docs.push(l); }
  eanCache = {v: memVer, lib: library, map}; return map;
}
function fratelloEan(lib){                 // un altro alias dello stesso codice con i valori dell'etichetta
  const g = eanIndice().get(eanDi(lib)); return g ? g.docs.find(d => d !== lib && d.nut) || null : null;
}
