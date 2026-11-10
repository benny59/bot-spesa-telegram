"use strict";
// ---------- Prodotti per codice (EAN): un codice = un prodotto, le voci negozio+descrizione sono alias ----------
function gruppiEan() {
  const out = [];
  for (const g of eanIndice().values()) {
    const kc = g.docs.filter(d => d.nut).map(d => Number(d.nut.kcal)).filter(isFinite);
    const incoerente = kc.length > 1 && (Math.max(...kc) - Math.min(...kc)) > 0.1 * Math.max(...kc, 1);   // stesso codice, etichette diverse
    out.push({ean: g.ean, docs: g.docs, incoerente});
  }
  return out.sort((a, b) => (b.incoerente - a.incoerente) || (b.docs.length - a.docs.length) || a.ean.localeCompare(b.ean));
}
function vecchiGtin() { return Object.values(library).filter(l => l.gtin && !l.ean); }
function renderEan() {
  const gs = gruppiEan(), vec = vecchiGtin();
  $("eanSum").textContent = t("ean.sum", {n: gs.length, a: gs.reduce((s, g) => s + g.docs.length, 0)});
  $("eanLegacy").style.display = vec.length ? "flex" : "none";
  $("eanLegacyBtn").textContent = t("ean.legacy", {n: vec.length});
  $("eanList").innerHTML = !gs.length ? `<p class="empty">${esc(t("ean.empty"))}</p>` : gs.slice(0, 40).map(g =>
    `<div class="lab-row"><div class="nm">⌗ ${esc(g.ean)}${g.incoerente ? ` <span class="chip fb">${esc(t("ean.mismatch"))}</span>` : ""}<small>${g.docs.map(d => esc((d.names && d.names[0] || "?") + " · " + (d.store || "?"))).join("<br>")}</small></div></div>`).join("");
}
$("eanLegacyBtn").addEventListener("click", async () => {
  const vec = vecchiGtin(); $("eanLegacyBtn").disabled = true;
  try {
    for (const l of vec) {
      const d = {...l, ean: l.gtin}; delete d.gtin; delete d.gtinAt;
      library[l.key] = d; memVer++;
      if (db && uid) await db.collection(COL).doc(d.id || prodDocId(l.key)).set(d);
    }
  } catch (e) { console.error(e); }
  $("eanLegacyBtn").disabled = false; renderEan(); renderMemory();
});
(function () { const ra = renderAll; renderAll = function () { try { ra(); } finally { try { renderEan(); } catch (e) { console.error(e); } } }; })();
renderEan();
