"use strict";
// ---------- Copia di sicurezza: esporta / importa tutti i dati in un file JSON ----------
// Il file contiene i documenti del database dell'artifact (scontrini, memoria dei prodotti con i codici EAN,
// preferiti importati, impostazioni...). Non contiene la foto degli scontrini né dati di pagamento.
const FORMATO_EXPORT = "basket-index-export";
let importaDocs = null;
function contaPerTipo(docs) { const c = {}; for (const d of docs) { const k = (d.data && d.data.kind) || "altro"; c[k] = (c[k] || 0) + 1; } return c; }
function descriviTipi(c) { return Object.entries(c).sort((a, b) => b[1] - a[1]).map(([k, n]) => n + " " + k).join(", ") || "-"; }
function renderBackup() {
  $("bkInfo").textContent = tuttiDocs.length ? t("bk.have", {n: tuttiDocs.length, x: descriviTipi(contaPerTipo(tuttiDocs))}) : t("bk.none");
  $("bkExport").disabled = !tuttiDocs.length;
}
$("bkExport").addEventListener("click", async () => {
  const out = {format: FORMATO_EXPORT, version: 1, exportedAt: new Date().toISOString(), docs: tuttiDocs.map(d => ({id: d.id, data: d.data}))};
  const testo = JSON.stringify(out, null, 1);
  const nome = "basket-index-" + new Date().toISOString().slice(0, 10) + ".json";
  let dl = null; try { dl = window.claude && claude.use ? await claude.use("downloads") : null; } catch (_) {}
  if (!dl) { $("bkStatus").textContent = t("bk.nodl"); $("bkText").value = testo; $("bkTextRow").style.display = "block"; return; }
  try { await dl.save({filename: nome, data: testo}); $("bkStatus").textContent = t("bk.saved", {n: out.docs.length}); }
  catch (e) { $("bkStatus").textContent = e && e.code === "declined" ? t("bk.declined") : t("bk.nodl"); if (!(e && e.code === "declined")) { $("bkText").value = testo; $("bkTextRow").style.display = "block"; } }
});
function validaImport(o) {
  if (!o || o.format !== FORMATO_EXPORT || !Array.isArray(o.docs)) return null;
  return o.docs.filter(d => d && typeof d.id === "string" && /^[A-Za-z0-9_-]{1,100}$/.test(d.id) && d.data && typeof d.data === "object" && typeof d.data.kind === "string");
}
$("bkFile").addEventListener("change", async e => {
  const f = e.target.files && e.target.files[0]; e.target.value = "";
  if (!f) return;
  let docs = null; try { docs = validaImport(JSON.parse(await f.text())); } catch (_) {}
  if (!docs || !docs.length) { importaDocs = null; $("bkPreview").textContent = t("bk.bad"); $("bkApply").style.display = "none"; return; }
  const esistenti = new Map(tuttiDocs.map(d => [d.id, d.data]));
  const nuovi = docs.filter(d => !esistenti.has(d.id)), uguali = docs.filter(d => esistenti.has(d.id) && JSON.stringify(esistenti.get(d.id)) === JSON.stringify(d.data));
  const diversi = docs.length - nuovi.length - uguali.length;
  importaDocs = docs.filter(d => !uguali.includes(d));
  $("bkPreview").textContent = t("bk.prev", {n: docs.length, x: descriviTipi(contaPerTipo(docs)), nuovi: nuovi.length, uguali: uguali.length, diversi});
  $("bkApply").style.display = importaDocs.length ? "inline-block" : "none";
  $("bkApply").textContent = t("bk.apply", {n: importaDocs.length});
});
$("bkApply").addEventListener("click", async () => {
  if (!importaDocs || !db || !uid) { $("bkPreview").textContent = t("bk.nodb"); return; }
  $("bkApply").disabled = true; let n = 0;
  try { for (const d of importaDocs) { await db.collection(COL).doc(d.id).set(d.data); n++; } $("bkPreview").textContent = t("bk.done", {n}); importaDocs = null; $("bkApply").style.display = "none"; }
  catch (e) { $("bkPreview").textContent = t("bk.fail", {n}); }
  $("bkApply").disabled = false;
});
(function () { const ra = renderAll; renderAll = function () { try { ra(); } finally { try { renderBackup(); } catch (e) { console.error(e); } } }; })();
renderBackup();
