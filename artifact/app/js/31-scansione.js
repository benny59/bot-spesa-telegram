"use strict";
// ---------- Scansione del codice a barre di un prodotto (Memoria dei prodotti → "Scan") ----------
// Si fotografa il codice a barre della confezione (la fotocamera del telefono). Lettura, in ordine:
// 1) BarcodeDetector del browser (sul telefono, gratis), 2) il modello Claude sulla foto, 3) digitazione a mano.
// Il codice è controllato con la cifra di controllo EAN e salvato come "ean" sul prodotto (negozio + descrizione).
let scanKey = null, scanMode = "key", scanEan = "";
function codiceValido(s) { return /^(\d{8}|\d{13})$/.test(s) && eanOk(s); }
async function leggiEanDaFoto(file) {
  if ("BarcodeDetector" in window) {
    try {
      const bd = new BarcodeDetector({formats: ["ean_13", "ean_8"]});
      const bmp = await createImageBitmap(file);
      const found = (await bd.detect(bmp)).map(c => c.rawValue).find(codiceValido);
      if (found) return found;
    } catch (e) {}
  }
  if (sample) {
    try {
      const out = await sample.json('Read the barcode in this photo of a product pack. Reply only JSON {"ean":"<the 13 or 8 digits printed under the barcode, or empty if you cannot read them reliably>"}', {images: [file]});
      const d = String((out && out.ean) || "").replace(/\D/g, "");
      if (codiceValido(d)) return d;
    } catch (e) {}
  }
  return "";
}
function apriScan(key) {
  const e = memoryEntries()[key]; if (!e) return;
  scanKey = key; scanMode = "key"; $("scanPick").style.display = "none";
  $("scanTarget").textContent = e.name + " · " + e.store;
  $("scanStatus").textContent = t("scan.photo");
  $("scanManualRow").hidden = false; $("scanManual").value = (eanDi(library[key])) || "";
  $("scanBox").hidden = false; $("scanBox").style.display = "flex";
  $("memScanInput").click();
}
function apriScanLibero() {
  scanKey = null; scanMode = "pick"; scanEan = "";
  $("scanTarget").textContent = t("cens.scan");
  $("scanStatus").textContent = t("scan.photo");
  $("scanPick").style.display = "none"; $("scanPick").innerHTML = "";
  $("scanManualRow").hidden = false; $("scanManual").value = "";
  $("scanBox").hidden = false; $("scanBox").style.display = "flex";
  $("memScanInput").click();
}
// Codice letto: si chiede a quale riga ancora da fare dell'ultimo scontrino (o di quello scelto) corrisponde.
function mostraScelta(ean) {
  scanEan = ean;
  const {righe} = righeCens();
  const gia = righe.find(x => eanDi(library[x.key]) === ean);
  const todo = righe.filter(x => statoRiga(x.key) === "todo");
  $("scanManualRow").hidden = false;
  if (gia || !todo.length) {
    scanEan = ""; $("scanPick").innerHTML = ""; $("scanPick").style.display = "none";
    $("scanStatus").textContent = gia ? t("cens.already", {x: gia.name}) : t("cens.alldone");
    return;
  }
  $("scanStatus").textContent = t("cens.which", {e: ean});
  $("scanPick").innerHTML = todo.map(x => `<button type="button" data-pick="${esc(x.key)}" style="text-align:left">${x.n > 1 ? x.n + "× " : ""}${esc(x.name)} · ${eur(x.price)}</button>`).join("");
  $("scanPick").style.display = "flex";
}
async function salvaGtin(key, ean) {
  const e = memoryEntries()[key]; if (!e) return false;
  const prev = library[key] || {};
  const doc = {...prev, kind: "product", id: prev.id || prodDocId(key), key, names: prev.names && prev.names.length ? prev.names : [e.name], store: prev.store || e.store, code: prev.code || e.code || "", ean, eanAt: new Date().toISOString()};
  library[key] = doc; memVer++;
  if (db && uid) await db.collection(COL).doc(doc.id).set(doc);
  return true;
}
function stessoCodice(key, ean) {            // lo stesso codice già censito su un altro negozio/descrizione
  return Object.values(library).filter(l => eanDi(l) === ean && l.key !== key).map(l => (l.names && l.names[0] || "?") + " (" + (l.store || "?") + ")");
}
let scanConferma = "";
async function concludiScan(ean) {
  const prevE = eanDi(library[scanKey]);
  if (prevE && prevE !== ean && scanConferma !== scanKey + "|" + ean) {      // non si sovrascrive in silenzio
    scanConferma = scanKey + "|" + ean; scanEan = ean;
    $("scanStatus").textContent = t("scan.replace", {old: prevE, e: ean});
    $("scanManualRow").hidden = false; $("scanManual").value = ean;
    return;
  }
  scanConferma = "";
  const ok = await salvaGtin(scanKey, ean);
  const altri = stessoCodice(scanKey, ean);
  $("scanStatus").textContent = ok ? t("scan.saved", {e: ean}) + (altri.length ? " " + t("scan.same", {x: altri.join(", ")}) : "") : t("scan.err");
  $("scanPick").style.display = "none";
  $("scanManualRow").hidden = scanMode === "key"; $("scanManual").value = "";
  renderMemory(); renderCens();
}
$("memCard").addEventListener("click", e => { const k = e.target.dataset && e.target.dataset.memscan; if (k) apriScan(k); });
$("memScanInput").addEventListener("change", async e => {
  const f = e.target.files && e.target.files[0]; e.target.value = "";
  if (!f || (!scanKey && scanMode !== "pick")) return;
  $("scanStatus").textContent = t("scan.reading");
  const ean = await leggiEanDaFoto(f);
  if (ean && scanMode === "pick") mostraScelta(ean);
  else if (ean) await concludiScan(ean);
  else { $("scanStatus").textContent = t("scan.fail"); $("scanManualRow").hidden = false; }
});
$("scanSave").addEventListener("click", async () => {
  const v = $("scanManual").value.replace(/\D/g, "");
  if (!codiceValido(v)) { $("scanStatus").textContent = t("scan.invalid"); return; }
  if (scanMode === "pick") mostraScelta(v); else await concludiScan(v);
});
$("scanAgain").addEventListener("click", () => $("memScanInput").click());
$("scanCancel").addEventListener("click", () => { scanKey = null; $("scanBox").hidden = true; $("scanBox").style.display = "none"; });

// ---------- Scheda "Scansiona gli articoli di uno scontrino" (di default l'ultimo salvato) ----------
let censSrc = "";
function righeCens() {
  const rs = cleanReceipts().slice().sort((a, b) => String(b.date).localeCompare(String(a.date)) || String(b.savedAt).localeCompare(String(a.savedAt)));
  if (!rs.some(r => r.id === censSrc)) censSrc = rs.length ? rs[0].id : "";
  const r = rs.find(x => x.id === censSrc);
  const righe = {};
  if (r) r.items.forEach(it => {
    if (it.cat === EXCLUDED || !(it.price > 0) || isSlip(it)) return;
    const key = itemKey(r.store, it);
    (righe[key] ||= {key, name: it.name, price: 0, n: 0}).n++; righe[key].price += it.price;
  });
  return {rs, r, righe: Object.values(righe)};
}
function statoRiga(key) { const l = library[key] || {}; return eanDi(l) ? "ok" : l.nogtin ? "no" : "todo"; }
function renderCens() {
  const {rs, r, righe} = righeCens(), sel = $("censSrc");
  sel.innerHTML = rs.map(x => `<option value="${esc(x.id)}">${esc(x.store)} · ${esc(x.date)}</option>`).join("");
  sel.value = censSrc; sel.hidden = !rs.length;
  const fatte = righe.filter(x => statoRiga(x.key) !== "todo").length;
  $("censProg").textContent = righe.length ? t("cens.prog", {a: fatte, b: righe.length}) : t("cens.none");
  $("censScan").disabled = !righe.length;
  $("censList").innerHTML = righe.map(x => {
    const s = statoRiga(x.key), l = library[x.key] || {};
    const stato = s === "ok" ? `<span class="chip">⌗ ${esc(eanDi(l))}</span>` : s === "no" ? `<span class="status">${esc(t("cens.nocode"))}</span>`
      : `<button type="button" data-censscan="${esc(x.key)}">${esc(t("scan.btn"))}</button> <button type="button" data-censno="${esc(x.key)}">${esc(t("cens.noBtn"))}</button>`;
    return `<div class="row" style="justify-content:space-between;gap:8px;padding:5px 0;border-top:1px solid var(--line)"><span style="min-width:0">${x.n > 1 ? x.n + "× " : ""}${esc(x.name)} <span class="status">${eur(x.price)}</span></span><span class="row" style="gap:6px">${stato}</span></div>`;
  }).join("");
}
$("censSrc").addEventListener("change", e => { censSrc = e.target.value; renderCens(); });
$("censScan").addEventListener("click", apriScanLibero);
$("scanPick").addEventListener("click", async e => { const k = e.target.dataset && e.target.dataset.pick; if (!k || !scanEan) return; scanKey = k; await concludiScan(scanEan); });
$("censList").addEventListener("click", async e => {
  const k = e.target.dataset && e.target.dataset.censscan; if (k) { apriScan(k); return; }
  const n = e.target.dataset && e.target.dataset.censno; if (!n) return;
  const en = memoryEntries()[n]; if (!en) return;
  const prev = library[n] || {};
  const doc = {...prev, kind: "product", id: prev.id || prodDocId(n), key: n, names: prev.names && prev.names.length ? prev.names : [en.name], store: prev.store || en.store, code: prev.code || en.code || "", nogtin: true};
  library[n] = doc; memVer++;
  if (db && uid) await db.collection(COL).doc(doc.id).set(doc);
  renderCens(); renderMemory();
});
(function () { const ra = renderAll; renderAll = function () { try { ra(); } finally { try { renderCens(); } catch (e) { console.error(e); } } }; })();
renderCens();
