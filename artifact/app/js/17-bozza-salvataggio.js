"use strict";
// ---------- Draft editing ----------
$("draftTable").addEventListener("change", e => {
  const ds = e.target.dataset;
  if (ds.g != null){ draft.items[+ds.g].g = e.target.value.trim(); return; }
  if (ds.sz != null){ const it = draft.items[+ds.sz]; it.size = e.target.value.trim(); if (parseSize(it.size)?.u !== "pc"){ delete it.w; delete it.wSrc; } renderDraft(); return; }
  if (ds.bio != null){ draft.items[+ds.bio].bio = e.target.checked; return; }
  const p = e.target.dataset.p;
  if (p != null){
    const v = parseFloat(e.target.value); if (!isFinite(v)) return;
    const it = draft.items[+p]; it.price = round2(v);
    if (it.unit !== "kg" && it.qty > 0) it.unitPrice = round2(v/it.qty);
    renderDraft(); return;
  }
  const i = e.target.dataset.i; if (i==null) return;
  draft.items[+i].cat = e.target.value; renderDraft(); if (!receipts.length) renderSummary();
});
$("dStore").addEventListener("change", e => draft && (draft.store = e.target.value));
$("dDate").addEventListener("change", e => draft && (draft.date = e.target.value));
$("discardBtn").onclick = () => { draft = null; draftIsExample = false; editingId = null; $("saveBtn").dataset.dupOk = ""; $("saveStatus").textContent=""; renderAll(); };
$("saveBtn").onclick = async () => {
  if (!draft) return;
  if (!draft.date){ $("saveStatus").textContent = "Add the receipt date before saving."; $("saveStatus").className="status err"; return; }
  if (!editingId && $("saveBtn").dataset.dupOk !== "1"){
    const twin = cleanReceipts().find(r => sig(r) === sig({...draft, total: draft.total ?? null}));
    if (twin){
      $("saveStatus").className = "status err";
      $("saveStatus").textContent = `This matches a receipt already saved (${chainLabel(twin.store)}, ${fmtDay(twin.date)}, ${eur(twin.total ?? receiptSum(twin))}). Tap Save again only if it is a different shop.`;
      $("saveBtn").dataset.dupOk = "1"; return;
    }
  }
  const prev = editingId ? receipts.find(r=>r.id===editingId) : null;
  const id = editingId || ("r-" + draft.date.replace(/-/g,"") + "-" + Date.now().toString(36));
  const ruleList = draft.items.filter(it => it._orig && it.cat !== EXCLUDED).map(it => ({store: draft.store, it: stripItem(it), ch: ruleChanges(it._orig, it)})).filter(x => Object.keys(x.ch).length);
  const rec = {kind:"receipt", id, store:draft.store||"", date:draft.date, total:draft.total||null, items:draft.items.map(stripItem), savedAt: prev?.savedAt || new Date().toISOString()};
  if (prev) rec.editedAt = new Date().toISOString();
  $("saveBtn").disabled = true;
  try {
    if (db && uid) await db.collection(COL).doc(id).set(rec);
    else { receipts = receipts.filter(r=>r.id!==id); receipts.push(rec); }
    const wasEdit = !!editingId;
    draft = null; draftIsExample = false; selected = id; editingId = null; $("saveBtn").dataset.dupOk = "";
    $("saveStatus").textContent = ""; renderAll();
    $("aiStatus").className = "status";
    $("aiStatus").textContent = !(db && uid) ? "Kept for this visit only (not signed in)." : wasEdit ? "Changes saved. Your index is updated above." : "Saved. Your index is updated above.";
    if (ruleList.length && db && uid){
      $("aiStatus").textContent += ` ${ruleList.length} correction${ruleList.length>1?"s":""} saved to product memory, so ${ruleList.length>1?"they apply":"it applies"} to every receipt with ${ruleList.length>1?"those products":"that product"}.`;
      saveRules(ruleList).catch(()=>{});
    }
  } catch(e){
    $("saveStatus").className = "status err";
    $("saveStatus").textContent = e.code==="quota_exceeded" ? "Storage is full. Delete some old receipts, then save again." : "Could not save right now. Try again in a moment.";
  } finally { $("saveBtn").disabled = false; }
};
$("history").addEventListener("click", async e => {
  const eid = e.target.dataset?.edit;
  if (eid){
    const r = receipts.find(x=>x.id===eid); if (!r) return;
    draft = clone({store:r.store, date:r.date, total:r.total, items:r.items.map(it => { const m = stripItem(withLib(r, it)); if (m.nutSrc === "photo" && it.nutSrc !== "photo"){ m.nut = it.nut; m.nutSrc = it.nutSrc; } return {...m, _orig:{cat:m.cat, g:m.g||"", bio:!!m.bio, size:m.size||"", ct:co2Type(m)}}; })}); draftIsExample = false; editingId = eid;
    $("saveStatus").textContent = ""; $("saveBtn").dataset.dupOk = "";
    renderDraft(); $("draftSec").scrollIntoView({behavior:"smooth", block:"start"}); return;
  }
  const id = e.target.dataset?.del; if (!id) return;
  const b = e.target;
  if (b.dataset.armed !== "1"){ b.dataset.armed="1"; b.textContent="Tap again to delete"; setTimeout(()=>{ if(b.isConnected){b.dataset.armed="";b.textContent="Delete";} },4000); return; }
  if (db && uid){ try { await db.collection(COL).doc(id).delete(); } catch(_){ b.textContent="Could not delete"; } }
  else { receipts = receipts.filter(r=>r.id!==id); renderAll(); }
});

// ---------- Rates editing ----------
let rateTimer = null;
$("ratesTable").addEventListener("change", e => {
  const k = e.target.dataset.k; if (!k) return;
  const v = parseFloat(e.target.value); if (!isFinite(v)) return;
  const o = latestOfficial();
  if (!overrides || overrides.month !== o.month) overrides = {month:o.month, rates:{}};
  overrides.rates[k] = v; renderSummary(); renderRates();
  clearTimeout(rateTimer); rateTimer = setTimeout(saveRates, 600);
});
$("resetRates").onclick = () => { overrides = null; renderRates(); renderSummary(); saveRates(); };
async function saveSettings(){
  if (!db || !uid) return;
  await db.collection(COL).doc("settings").set({kind:"settings", overrides: overrides || null, household, spices: spiceShelf || "", week, planOpts, athlete});
}
async function saveRates(){
  if (!db || !uid){ $("ratesStatus").textContent = "Applied for this visit."; return; }
  try { await saveSettings(); $("ratesStatus").textContent = overrides ? "Saved." : "Reset."; }
  catch(_){ $("ratesStatus").textContent = "Could not save the rates."; }
}
