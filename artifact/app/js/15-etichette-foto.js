"use strict";
function labelCandidates(){
  const m = {};
  for (const r of cleanReceipts()) for (const it of r.items){
    if (!isFood(it) || /beleg|theke|bedien/i.test(it.name)) continue;
    if (isLabelled(withLib(r, it))) continue;
    const k = itemKey(r.store, it), lib = library[k];
    const c = (m[k] ||= {key:k, name:it.name, g:it.g||"", store:chainLabel(r.store), code:it.code||"", spend:0, n:0, pending: !!(lib && lib.ean && !lib.nut)});
    c.spend += it.price; c.n++;
  }
  return Object.values(m).sort((a,b)=>b.spend-a.spend);
}
function renderLabels(){
  const card = $("labCard");
  if (!db || !uid){ card.hidden = true; return; }
  card.hidden = false;
  const cands = labelCandidates(), shown = labShowAll ? cands : cands.slice(0, 8);
  $("labCount").textContent = cands.length ? `${cands.length} product${cands.length>1?"s":""} with typical values` : "";
  $("labList").innerHTML = !cands.length ? `<p class="empty">Every product you've bought has label data.</p>` :
    shown.map((c,i) => `<div class="lab-row"><div class="nm">${esc(c.name)}${c.pending?' <span class="chip fb">barcode saved, values to look up</span>':""}<small>${esc(c.store)}${c.code?" · "+esc(c.code):""} · ${c.n}× · ${eur(c.spend)}</small></div>
      <button type="button" id="lab-${i}" data-lab="${esc(c.key)}">${c.pending?"Add nutrition photo":"Add label"}</button></div>`).join("")
    + (cands.length > 8 ? `<div style="margin-top:8px"><button type="button" id="labMore">${labShowAll ? "Show fewer" : `Show all ${cands.length}`}</button></div>` : "");
  const libs = Object.values(library).filter(l => l.nut || l.ean);
  $("labLibBox").hidden = !libs.length;
  $("labLibSum").textContent = `Saved labels (${libs.length})`;
  $("labLib").innerHTML = libs.sort((a,b)=>String(b.addedAt).localeCompare(String(a.addedAt))).map(l => `<div class="lab-row"><div class="nm">${esc([l.brand,l.product].filter(Boolean).join(" ") || l.names?.[0] || "Product")}<small>${esc(l.store||"")} · receipt: ${esc(l.names?.[0]||"")}${l.ean?" · EAN "+esc(l.ean):""}${l.nut?` · ${Math.round(l.nut.kcal)} kcal/100 g`:" · values to look up"}</small></div>
    <button type="button" data-libdel="${esc(l.id)}" id="libdel-${esc(l.id)}">Delete</button></div>`).join("");
}
function eanOk(s){
  if (!/^(\d{8}|\d{13})$/.test(s)) return false;
  const d = s.split("").map(Number), chk = d.pop(); let sum = 0;
  d.reverse().forEach((x,i) => sum += x*(i%2===0 ? 3 : 1));
  return (10 - sum%10) % 10 === chk;
}
const LF = ["kcal","f","sf","c","s","fib","p","salt"];
function openLabPanel(key){
  const c = labelCandidates().find(x=>x.key===key); if (!c) return;
  labTarget = c; labFiles = []; labExtra = {ns:"", mic:{}};
  $("labTarget").textContent = `${c.name} · ${c.store}`;
  $("labThumbs").innerHTML = ""; $("labStatus").textContent = sample ? "Photograph the nutrition table. A barcode photo helps if the table is hard to read." : "Reading photos is not available in this view; you can type the values from the label instead.";
  $("labRead").disabled = true; $("labSaveStatus").textContent = "";
  for (const id of ["brand","product","ean","size","drained",...LF]) $("lf-"+id).value = "";
  $("lf-per").value = "100 g";
  const lib = library[key]; if (lib){ $("lf-brand").value = lib.brand||""; $("lf-product").value = lib.product||""; $("lf-ean").value = lib.ean||""; $("lf-size").value = lib.size||""; }
  $("labReview").hidden = !!sample && !lib; $("labCheck").textContent = "";
  $("labPanel").hidden = false; $("labPanel").scrollIntoView({behavior:"smooth", block:"nearest"});
}
$("labList").addEventListener("click", e => {
  if (e.target.id === "labMore"){ labShowAll = !labShowAll; renderLabels(); return; }
  const k = e.target.dataset?.lab; if (k) openLabPanel(k);
});
$("labCancel").onclick = () => { labCtl?.abort(); $("labPanel").hidden = true; labTarget = null; };
$("labPhotos").addEventListener("change", async e => {
  const files = [...(e.target.files||[])];
  const lim = sample ? await sample.limits().catch(()=>null) : null;
  const max = lim?.images?.maxCount || 3;
  labFiles = files.slice(0, max);
  $("labThumbs").innerHTML = labFiles.map((f,i)=>`<img alt="Label photo ${i+1}" src="${URL.createObjectURL(f)}">`).join("");
  $("labRead").disabled = !sample || !labFiles.length;
  $("labStatus").textContent = files.length > max ? `Using the first ${max} photos.` : (sample ? "Tap “Read label”." : "");
});
const LABEL_PROMPT = `These photos show one grocery product bought in Germany: its nutrition table, barcode and/or front of pack. Copy what is printed; do not estimate.
- brand, product: as on the pack.
- ean: the digits printed under the barcode (8 or 13 digits), or "" if no barcode is visible.
- size: net quantity as printed (e.g. "400 g", "1 l"); drained: drained weight if printed ("Abtropfgewicht"), else "".
- per: the column you used, "100 g" or "100 ml" (use the per-100 column, not per portion).
- nut: per-100 values {"kcal","f","sf","c","s","fib","p","salt"} = energy kcal, fat, saturates, carbohydrate, sugars, fibre, protein, salt in g. If only kJ is printed, kcal = kJ / 4.184. Use null for anything not printed or not legible.
- ns: the Nutri-Score letter if a Nutri-Score logo is printed on the pack (the highlighted letter), else "".
- mic: vitamins and minerals per 100 only if printed (fortified products): {"vc" mg,"va" µg,"vd" µg,"b12" µg,"fol" µg,"ca" mg,"fe" mg,"mg" mg,"k" mg,"zn" mg}, null for those not printed.
Reply with only JSON: {"brand":"","product":"","ean":"","size":"","drained":"","per":"100 g","ns":"","nut":{"kcal":null,"f":null,"sf":null,"c":null,"s":null,"fib":null,"p":null,"salt":null},"mic":{}}`;
$("labRead").onclick = async () => {
  if (!sample || !labFiles.length || !labTarget) return;
  labCtl = new AbortController(); $("labRead").disabled = true;
  $("labStatus").className = "status"; $("labStatus").textContent = "Reading the label… about 20–40 seconds.";
  try {
    const out = await sample.json(LABEL_PROMPT + `\n\nOn the receipt this product appears as “${labTarget.name}” at ${labTarget.store}.`, {images: labFiles, signal: labCtl.signal});
    $("lf-brand").value = String(out?.brand||""); $("lf-product").value = String(out?.product||"");
    $("lf-ean").value = String(out?.ean||"").replace(/\D/g,""); $("lf-size").value = String(out?.size||""); $("lf-drained").value = String(out?.drained||"");
    $("lf-per").value = String(out?.per||"100 g");
    for (const k of LF){ const v = out?.nut?.[k]; $("lf-"+k).value = (v===null || v===undefined || v==="") ? "" : Number(v); }
    labExtra = {ns: /^[A-E]$/.test(String(out?.ns||"").toUpperCase()) ? String(out.ns).toUpperCase() : "", mic: {}};
    if (out?.mic && typeof out.mic === "object") for (const m of MIC){ const v = Number(out.mic[m.k]); if (out.mic[m.k] != null && isFinite(v) && v >= 0) labExtra.mic[m.k] = v; }
    $("labReview").hidden = false; checkLabel();
    $("labStatus").textContent = "Check the values against the pack, then save.";
  } catch(e){
    $("labStatus").className = "status err";
    $("labStatus").textContent = e?.code === "cancelled" ? "Stopped." : e?.code === "not_granted" ? "Reading photos needs your permission to use Claude on this page." : e?.code === "invalid_json" ? "The label couldn't be read cleanly. Try a sharper, straight-on photo of the table." : "Something went wrong reading the label. Try again, or type the values in.";
    $("labReview").hidden = false;
  } finally { $("labRead").disabled = !labFiles.length; }
};
function labValues(){ const n = {}; let any = false; for (const k of LF){ const v = $("lf-"+k).value.trim(); if (v !== "" && isFinite(+v)){ n[k] = +v; any = true; } } return any ? n : null; }
function checkLabel(){
  const n = labValues(), ean = $("lf-ean").value.trim(), msgs = [];
  if (ean) msgs.push(eanOk(ean) ? `<span class="ok">Barcode checks out.</span>` : `<span class="up">Barcode digits don't pass the check digit; compare with the pack.</span>`);
  if (n && n.kcal > 0 && [n.p,n.f,n.c].every(v=>v!=null)){
    const est = 4*n.p + 9*n.f + 4*n.c + 2*(n.fib||0), off = Math.abs(est - n.kcal)/n.kcal;
    msgs.push(off > 0.15 ? `<span class="up">Energy doesn't match the nutrients (${Math.round(est)} kcal from protein, fat and carbs vs ${Math.round(n.kcal)} printed); check a value.</span>` : `<span class="ok">Energy matches the nutrients.</span>`);
  }
  if (n && n.salt > 10) msgs.push(`<span class="up">Salt above 10 g per 100 g is unusual; check it.</span>`);
  if (!n && ean) msgs.push("Only the barcode so far: it will be saved so the values can be looked up in a product database.");
  $("labCheck").innerHTML = msgs.join(" ");
}
$("labReview").addEventListener("input", checkLabel);
$("labSave").onclick = async () => {
  if (!labTarget || !db || !uid) return;
  const n = labValues(), ean = $("lf-ean").value.trim().replace(/\D/g,"");
  if (!n && !ean){ $("labSaveStatus").textContent = "Add the nutrition values or the barcode first."; return; }
  const nut = n ? Object.fromEntries(LF.map(k=>[k, n[k] ?? 0])) : null;
  const missing = n ? LF.filter(k => n[k] == null) : [];
  const sz = parseSize($("lf-drained").value) || parseSize($("lf-size").value);
  const w = sz && sz.u !== "pc" ? sz.q*(sz.u==="l"?1.03:1) : null;
  const id = prodDocId(labTarget.key);
  const doc = {kind:"product", id, key:labTarget.key, names:[labTarget.name], store:labTarget.store, code:labTarget.code,
    brand:$("lf-brand").value.trim(), product:$("lf-product").value.trim(), ean, size:$("lf-size").value.trim(), drained:$("lf-drained").value.trim(),
    per:$("lf-per").value.trim() || "100 g", w, nut, missing, ns: labExtra.ns, micPrinted: labExtra.mic, src:"photo", addedAt:new Date().toISOString()};
  const prev = library[labTarget.key]; if (prev?.nogtin) doc.nogtin = prev.nogtin; if (!doc.ean && prev?.gtin) doc.ean = prev.gtin; if (prev?.rule) doc.rule = prev.rule; if (prev?.est) doc.est = prev.est;
  $("labSave").disabled = true;
  try {
    await db.collection(COL).doc(id).set(doc);
    $("labPanel").hidden = true; labTarget = null;
    $("nutFillStatus").textContent = "";
  } catch(_){ $("labSaveStatus").textContent = "Couldn't save just now. Try again in a moment."; }
  finally { $("labSave").disabled = false; }
};
$("labLib").addEventListener("click", async e => {
  const id = e.target.dataset?.libdel; if (!id) return; const b = e.target;
  if (b.dataset.armed !== "1"){ b.dataset.armed = "1"; b.textContent = "Tap again to delete"; setTimeout(()=>{ if (b.isConnected){ b.dataset.armed=""; b.textContent="Delete"; } }, 4000); return; }
  const l = Object.values(library).find(x => x.id === id);
  try {
    if (l && l.rule){ const keep = {kind:"product", id, key:l.key, names:l.names, store:l.store, code:l.code, rule:l.rule, ruleAt:l.ruleAt}; if (l.est) keep.est = l.est; await db.collection(COL).doc(id).set(keep); }
    else await db.collection(COL).doc(id).delete();
  } catch(_){ b.textContent = "Couldn't delete"; }
});
$("nutPeriod").addEventListener("click", e => { const b = e.target.closest("button[data-np]"); if (!b) return; nutPeriod = b.dataset.np; renderNutrition(); });

// Estimate weight and nutrition for saved food lines that have none (text only, one call).
$("nutFill").onclick = async () => {
  const todo = [];
  for (const r of cleanReceipts()) r.items.forEach((it, idx) => { if (isFood(it) && (!it.nut || !it.mic || !it.fat2) && !/beleg|theke|bedien/i.test(it.name)) todo.push({r, idx, it}); });
  if (!todo.length || !sample) return;
  const uniq = {}; todo.forEach(t => { const k = (t.it.code||"") + "|" + t.it.name; (uniq[k] ||= {k, name:t.it.name, g:t.it.g||"", size:t.it.size||"", unit:t.it.unit, store:t.r.store}); });
  const rows = Object.values(uniq).slice(0, 120);
  $("nutFill").disabled = true; $("nutFillStatus").className = "status"; $("nutFillStatus").textContent = `Estimating ${rows.length} products… this takes up to a minute.`;
  try {
    const out = await sample.json(NUT_PROMPT + "\n\nProducts:\n" + JSON.stringify(rows.map((r,i)=>({i, name:r.name, generic:r.g, size:r.size, sold:r.unit==="kg"?"by weight":"by pack/piece", store:r.store}))), {});
    const byI = Array.isArray(out) ? out : (out?.items || []);
    const est = {}; for (const e of byI){ const r = rows[Number(e.i)]; if (r && e.nut) est[r.k] = e; }
    const changed = new Map();
    for (const t of todo){ const e = est[(t.it.code||"") + "|" + t.it.name]; if (!e) continue;
      const rec = changed.get(t.r.id) || clone(receipts.find(x => x.id === t.r.id) || t.r); rec.items = rec.items.map(stripItem); const it = rec.items[t.idx];
      if (it.nut && isLabelled(it)){ const keep = {nut:it.nut, nutSrc:it.nutSrc, nutRef:it.nutRef, nutNote:it.nutNote, w:it.w, wSrc:it.wSrc}; applyNut(it, e); Object.assign(it, keep); }
      else applyNut(it, e);
      changed.set(t.r.id, rec); }
    let n = 0; for (const rec of changed.values()){ await db.collection(COL).doc(rec.id).set(rec); n++; }
    $("nutFillStatus").textContent = `Added estimates to ${Object.keys(est).length} products on ${n} receipt${n===1?"":"s"}.`;
  } catch(e){
    $("nutFillStatus").className = "status err";
    $("nutFillStatus").textContent = e?.code === "not_granted" ? "Estimating needs your permission to use Claude on this page." : "The estimate didn't come through. Try again in a moment.";
  } finally { $("nutFill").disabled = false; }
};
function applyNut(it, e){
  const n = e.nut || {}; const clean = {};
  for (const x of NUT){ if (x.x || x.calc || x.co2) continue; const v = Number(n[x.k]); clean[x.k] = isFinite(v) && v >= 0 ? Math.min(v, x.k==="kcal" ? 900 : 100) : 0; }
  it.nut = clean; it.nutSrc = "typical"; delete it.nutRef; delete it.nutNote;
  const ep = Number(e.ep); it.ep = isFinite(ep) && ep > 0 && ep <= 1 ? ep : 1;
  if (it.unit !== "kg"){ const w = Number(e.w); if (isFinite(w) && w > 0 && w < 20){ it.w = w; it.wSrc = e.wSrc === "label" ? "label" : "est"; } }
  if (e.mic && typeof e.mic === "object"){ const m = {}; for (const x of MIC){ const v = Number(e.mic[x.k]); m[x.k] = isFinite(v) && v >= 0 ? Math.min(v, 5000) : 0; } it.mic = m; }
  if (["food","bev","water","fat","cheese","redmeat"].includes(e.nsType)) it.nsType = e.nsType;
  if (e.fat2 && typeof e.fat2 === "object"){ const f2 = {}; for (const k of ["mufa","pufa","n3"]){ const v = Number(e.fat2[k]); f2[k] = isFinite(v) && v >= 0 ? Math.min(v, 100) : 0; } it.fat2 = f2; }
  if (e.wg != null && isFinite(Number(e.wg))) it.wg = Math.max(0, Math.min(100, Number(e.wg)));
  const fv = Number(e.fvl); if (isFinite(fv)) it.fvl = Math.max(0, Math.min(100, fv));
}
const NUT_PROMPT = `For each grocery product below (German supermarket receipt names), estimate:
- nut: typical nutrition per 100 g of the edible part, as on an EU label: {"kcal","p" (protein g),"f" (fat g),"sf" (saturated fat g),"c" (available carbohydrate g),"s" (sugars g),"fib" (fibre g),"salt" (g)}. Use standard food-composition values for that kind of product; for dry goods (pasta, rice, oats) use the dry values.
- w: net weight in kg of one pack or piece as sold (drained weight for tinned or jarred goods; 1 l of milk = 1.03). For products sold by weight, give 1. Use the printed size when there is one ("wSrc":"label"), otherwise a typical pack or piece weight for that product in German shops ("wSrc":"est").
- ep: edible fraction of what is sold (bananas 0.65, mango 0.7, eggs 0.88, most packaged foods 1).
- mic: typical per 100 g edible part {"vc" vitamin C mg,"va" vitamin A µg RAE,"vd" vitamin D µg,"b12" µg,"fol" folate µg,"ca" mg,"fe" mg,"mg" mg,"k" mg,"zn" mg}.
- fat2: typical per 100 g {"mufa" monounsaturated g,"pufa" polyunsaturated g,"n3" omega-3 g (ALA+EPA+DHA)}.
- wg: for grain products only (bread, pasta, rice, cereals, flour, crackers), % of the grain that is wholegrain (0–100); omit for everything else.
- nsType: Nutri-Score category "bev" (drinks incl. milk, kefir, plant drinks, juices), "water", "fat" (oils, butter, spreads, cream, nuts, seeds), "cheese", "redmeat", else "food"; fvl: % fruit, vegetables and legumes (not potatoes, nuts or soy products).
Reply with only a JSON array: [{"i":0,"w":0.5,"wSrc":"label","ep":1,"nut":{"kcal":350,"p":13,"f":2,"sf":0.4,"c":68,"s":3,"fib":6,"salt":0},"mic":{"vc":0,"va":0,"vd":0,"b12":0,"fol":18,"ca":20,"fe":1.5,"mg":50,"k":180,"zn":1.3},"nsType":"food","fvl":0,"fat2":{"mufa":0.3,"pufa":0.9,"n3":0.04},"wg":100}]`;
