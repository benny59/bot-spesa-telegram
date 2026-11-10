"use strict";
// =====================================================================
// Product memory: what the page knows about each product you've bought
// =====================================================================
// The latest saved line of each product (raw, as read) and how it reads after your rules (eff).
function memoryEntries(){
  const out = {};
  const raw = [...receipts].sort((a,b) => a.date.localeCompare(b.date) || String(a.savedAt).localeCompare(String(b.savedAt)));
  for (const r of raw) for (const it of r.items){
    if (it.cat === EXCLUDED || !(it.price > 0) || isSlip(it)) continue;
    const key = itemKey(r.store, it);
    const e = (out[key] ||= {key, chain: chainOf(r.store), store: chainLabel(r.store), code: it.code||"", n: 0, spend: 0});
    e.n++; e.spend += it.price; e.last = r.date; e.name = it.name; e.raw = it; e.eff = withLib(r, it);
  }
  for (const k in library){ const l = library[k]; if (!out[k] && l.rule) out[k] = {key:k, chain:String(k).split("|")[0], store:l.store||"", code:l.code||"", n:0, spend:0, name:l.names?.[0]||"", raw:null, eff:null, orphan:true}; }
  return out;
}
function memoryIndex(){
  const ent = memoryEntries(), byCode = {}, byName = {};
  for (const e of Object.values(ent)){ if (!e.raw) continue; if (e.code) byCode[e.chain+"|"+e.code] = e; byName[e.chain+"|"+String(e.name).toLowerCase().replace(/[^a-z0-9äöüß]+/g,"")] = e; }
  return {ent, byCode, byName};
}
function memFind(idx, store, it){
  const ch = chainOf(store);
  return idx.ent[itemKey(store, it)]?.raw ? idx.ent[itemKey(store, it)] : (it.code && idx.byCode[ch+"|"+it.code]) || idx.byName[ch+"|"+String(it.name||"").toLowerCase().replace(/[^a-z0-9äöüß]+/g,"")] || null;
}
// Products already known, listed in the reading prompt so the photo only needs the till data for them.
function knownList(idx){
  const by = {};
  for (const e of Object.values(idx.ent).filter(e => e.raw && isFood(e.eff) && e.eff.nut).sort((a,b)=>b.last.localeCompare(a.last)).slice(0, 400))
    (by[e.store] ||= []).push(`${e.code || "–"} ${e.name} = ${e.eff.g || ""}`);
  return Object.entries(by).map(([st, l]) => `${st}: ${l.join("; ")}`).join("\n");
}
const MEM_FIELDS = ["cat","g","bio","size","w","wSrc","ep","nut","fat2","wg","mic","nsType","fvl","ct"];
function fromMemory(it, e){
  const m = {...it};
  for (const k of MEM_FIELDS){ if (e.raw[k] !== undefined) m[k] = clone(e.raw[k]); }
  if (e.raw.nutSrc && e.raw.nutSrc !== "typical") m.nutSrc = e.raw.nutSrc; else if (m.nut) m.nutSrc = "typical";
  if (it.unit === "kg"){ m.size = ""; m.w = 1; m.wSrc = "label"; }
  m._mem = 1; return m;
}
const CT_KEYS = Object.keys(CO2T).join(", ");
const CLASSIFY_PROMPT = () => `Classify each grocery line below (German supermarket receipt text) and estimate its nutrition.
${RECEIPT_CLASSES}
For each line give: cat (class key), g (short generic English name without brand or "organic", reusing a name from the list below when it is the same kind of product), bio (true if organic), size (pack size as printed or reliably known, "" if unsure or weighed), ct (climate type, one of: ${CT_KEYS}), and the nutrition fields:
${NUT_PROMPT.split("\n").slice(1, 9).join("\n")}
Reply with only a JSON array: [{"i":0,"cat":"dairy","g":"Mozzarella","bio":true,"size":"125 g","ct":"freshcheese","w":0.125,"wSrc":"label","ep":1,"nut":{"kcal":250,"p":18,"f":19,"sf":13,"c":1,"s":1,"fib":0,"salt":0.5},"mic":{"vc":0,"va":180,"vd":0.3,"b12":1.5,"fol":10,"ca":400,"fe":0.3,"mg":20,"k":80,"zn":2.5},"nsType":"cheese","fvl":0,"fat2":{"mufa":5.5,"pufa":0.6,"n3":0.2}}]`;
async function classifyItems(store, items, signal){
  if (!items.length) return;
  const gen = [...new Set(cleanReceipts().flatMap(r=>r.items.map(i=>i.g).filter(Boolean)))].slice(0,250);
  const rows = items.map((it,i) => ({i, name: it.name, code: it.code, sold: it.unit === "kg" ? "by weight" : "by pack/piece", price: it.price, store}));
  const out = await sample.json(CLASSIFY_PROMPT() + "\n\nGeneric names in use: " + gen.join("; ") + "\n\nLines:\n" + JSON.stringify(rows), {signal});
  const arr = Array.isArray(out) ? out : (out?.items || []);
  for (const e of arr){
    const it = items[Number(e.i)]; if (!it) continue;
    if (CAT[e.cat] || e.cat === EXCLUDED) it.cat = e.cat;
    if (typeof e.g === "string") it.g = e.g.trim().slice(0,60);
    it.bio = !!e.bio; if (typeof e.size === "string" && it.unit !== "kg") it.size = e.size.trim().slice(0,20);
    if (CO2T[e.ct]) it.ct = e.ct;
    if (isFood(it) && e.nut && typeof e.nut === "object") applyNut(it, e);
  }
}
// One correction → a rule for that product, applied to every receipt it's on, past and future.
function ruleChanges(base, it){
  const ch = {};
  if ((it.g||"") !== (base.g||"") && it.g) ch.g = it.g;
  if (it.cat !== base.cat) ch.cat = it.cat;
  if (!!it.bio !== !!base.bio) ch.bio = !!it.bio;
  if (it.unit !== "kg" && (it.size||"") !== (base.size||"")) ch.size = it.size||"";
  if (it.ct && co2Type(it) !== co2Type(base)) ch.ct = it.ct;
  return ch;
}
async function saveRules(list){        // list: [{store, it, ch}]
  if (!db || !uid || !list.length) return 0;
  const toEstimate = [];
  for (const {store, it, ch} of list){
    const key = itemKey(store, it), id = prodDocId(key), prev = library[key] || {};
    const rule = {...(prev.rule||{}), ...ch};
    const doc = {...prev, kind:"product", id, key, names: prev.names?.length ? prev.names : [it.name], store: prev.store || chainLabel(store), code: it.code||"", rule, ruleAt: new Date().toISOString()};
    if (ch.cat || ch.g) delete doc.est;
    library[key] = doc; memVer++;
    await db.collection(COL).doc(id).set(doc);
    if ((ch.cat || ch.g) && isFood({...it, ...rule}) && sample) toEstimate.push({key, id, name: it.name, g: rule.g || it.g || "", size: rule.size ?? it.size ?? "", unit: it.unit, store});
  }
  if (toEstimate.length){
    try {
      const out = await sample.json(NUT_PROMPT + "\nAlso give ct, the climate type, one of: " + CT_KEYS + ".\n\nProducts:\n" + JSON.stringify(toEstimate.map((t,i)=>({i, name:t.name, generic:t.g, size:t.size, sold:t.unit==="kg"?"by weight":"by pack/piece", store:t.store}))), {});
      const arr = Array.isArray(out) ? out : (out?.items || []);
      for (const e of arr){
        const t = toEstimate[Number(e.i)]; if (!t || !e.nut) continue;
        const tmp = {unit: t.unit}; applyNut(tmp, e);
        const est = {nut: tmp.nut, ep: tmp.ep, w: tmp.w || null, mic: tmp.mic || null, fat2: tmp.fat2 || null, wg: tmp.wg ?? null, nsType: tmp.nsType || null, fvl: tmp.fvl ?? null, ct: CO2T[e.ct] ? e.ct : null, at: new Date().toISOString()};
        const cur = library[t.key]; if (!cur) continue;
        await db.collection(COL).doc(t.id).set({...cur, est});
      }
    } catch(_){}
  }
  return list.length;
}

// ---------- Product memory card ----------
let memQuery = "", memFilter = "all", memEdit = null, memAll = false;
function memBadges(e){
  const l = library[e.key] || {}, b = [];
  if (l.rule) b.push(`<span class="chip mem-rule">your rule</span>`);
  if (l.nut) b.push(`<span class="chip mem-lab">label</span>`);
  if (eanDi(l)) b.push(`<span class="chip" title="${esc(t("scan.gtin"))}">⌗ ${esc(eanDi(l))}</span>`);
  const fc = favChip(e.eff || {}); if (fc) b.push(fc);
  return b.join(" ");
}
function renderMemory(){
  const card = $("memCard"); if (!card) return;
  const ent = Object.values(memoryEntries()).filter(e => !e.orphan || library[e.key]?.rule);
  const q = memQuery.trim().toLowerCase();
  let list = ent.filter(e => {
    const l = library[e.key] || {};
    if (memFilter === "rule" && !l.rule) return false;
    if (memFilter === "label" && !l.nut) return false;
    if (memFilter === "typical" && (l.nut || !e.eff?.nut)) return false;
    if (q && !`${e.name} ${e.eff?.g||""} ${e.store} ${e.code}`.toLowerCase().includes(q)) return false;
    return true;
  }).sort((a,b) => (b.n - a.n) || String(b.last).localeCompare(String(a.last)));
  const nRule = ent.filter(e => library[e.key]?.rule).length, nLab = ent.filter(e => library[e.key]?.nut).length;
  const shown = memAll || q ? list : list.slice(0, 25);
  const catOpts = cur => CATS.map(c => `<option value="${c.k}"${cur===c.k?" selected":""}>${esc(c.n)}</option>`).join("") + `<option value="${EXCLUDED}"${cur===EXCLUDED?" selected":""}>Not counted (deposit, bag)</option>`;
  const ctOpts = cur => Object.entries(CO2T).sort((a,b)=>a[1][1].localeCompare(b[1][1])).map(([k,[v,n]]) => `<option value="${k}"${cur===k?" selected":""}>${esc(n)} · ${v.toLocaleString("de-DE")} kg/kg</option>`).join("");
  const row = e => {
    const it = e.eff || {}, ct = it.name ? co2Type(it) : "other";
    const vn = nomeVoce(it);
    const head = `<div class="mem-row${memEdit === e.key ? " open" : ""}"><div class="nm">${vn ? `<input type="checkbox" data-memsel="${esc(vn)}" aria-label="${esc(t("mem.select"))}"${ponteSpunte.has(vn) ? " checked" : ""} style="margin-right:6px">` : ""}${esc(e.name)} ${memBadges(e)}<small>${esc(e.store)}${e.code ? " · "+esc(e.code) : ""} · ${e.n}× · last ${e.last ? esc(fmtDay(e.last)) : "–"}</small>
        <small>${esc(it.g || "no generic name")} · ${esc(CAT[it.cat]?.n || (it.cat===EXCLUDED ? "not counted" : "–"))}${it.size ? " · "+esc(it.size) : ""}${it.bio ? " · organic" : ""}${isFood(it) ? " · "+esc(CO2T[ct][1]) : ""}</small></div>
      <button type="button" data-memscan="${esc(e.key)}">${esc(t("scan.btn"))}</button>
      <button type="button" data-memedit="${esc(e.key)}" aria-expanded="${memEdit === e.key}">${memEdit === e.key ? "Close" : "Edit"}</button></div>`;
    if (memEdit !== e.key) return head;
    const l = library[e.key] || {};
    return head + `<div class="mem-form" data-memform="${esc(e.key)}">
      <label>Compare as<input type="text" id="mf-g" value="${esc(it.g||"")}" maxlength="60"></label>
      <label>Class<select id="mf-cat">${catOpts(it.cat)}</select></label>
      <label>Pack size<input type="text" id="mf-size" value="${esc(it.size||"")}" placeholder="${it.unit==="kg"?"sold by weight":"e.g. 500 g"}" ${it.unit==="kg"?"disabled":""} maxlength="20"></label>
      <label>Climate type<select id="mf-ct">${ctOpts(ct)}</select></label>
      <label class="chk"><input type="checkbox" id="mf-bio" ${it.bio?"checked":""}> organic</label>
      <div class="row"><button type="button" class="primary" data-memsave="${esc(e.key)}">Save rule</button>${l.rule ? `<button type="button" data-memdel="${esc(e.key)}">Remove rule</button>` : ""}<span class="status" id="memStatus" aria-live="polite"></span></div>
      <p class="note" style="margin:0">A rule applies to this product on every receipt, past and future${l.nut ? "; its label values stay as they are" : ""}. Changing the class or name also refreshes its typical nutrition.</p></div>`;
  };
  card.innerHTML = `<div class="row" style="justify-content:space-between;gap:8px">
      <input type="search" id="memSearch" placeholder="Search products" value="${esc(memQuery)}" aria-label="Search product memory" style="flex:1 1 12em;min-width:0">
      <div class="chips" id="memFilter" role="group" aria-label="Show">${[["all",`All ${ent.length}`],["rule",`Your rules ${nRule}`],["label",`Label data ${nLab}`],["typical","Typical values"]].map(([k,n])=>`<button type="button" data-mf="${k}" aria-pressed="${k===memFilter}">${n}</button>`).join("")}</div></div>
    <div class="mem-list">${shown.length ? shown.map(row).join("") : `<p class="empty">${ent.length ? "Nothing matches." : "Products appear here once you've saved a receipt."}</p>`}</div>
    ${list.length > shown.length ? `<button type="button" id="memMore" style="margin-top:8px">Show all ${list.length}</button>` : ""}
    <p class="note" style="margin-top:8px">The page remembers every product by store and article number. When you read a new receipt, products it already knows are filled in from here, so reading is quicker and the same product is always counted the same way. Corrections you make on a receipt become rules here.</p>`;
}
$("memCard").addEventListener("change", e => { const c = e.target.closest("input[data-memsel]"); if (c && typeof togglaVoce === "function") togglaVoce(c.dataset.memsel, c.checked); });
$("memCard").addEventListener("input", e => { if (e.target.id === "memSearch"){ memQuery = e.target.value; const pos = e.target.selectionStart; renderMemory(); const s = $("memSearch"); s.focus(); try { s.setSelectionRange(pos, pos); } catch(_){} } });
$("memCard").addEventListener("click", async e => {
  const f = e.target.closest("button[data-mf]"); if (f){ memFilter = f.dataset.mf; renderMemory(); return; }
  if (e.target.id === "memMore"){ memAll = true; renderMemory(); return; }
  const ek = e.target.dataset?.memedit; if (ek){ memEdit = memEdit === ek ? null : ek; renderMemory(); return; }
  const sk = e.target.dataset?.memsave, dk = e.target.dataset?.memdel;
  if (!sk && !dk) return;
  if (!db || !uid){ $("memStatus").textContent = "Saving rules needs you signed in."; return; }
  const ent = memoryEntries()[sk || dk];
  e.target.disabled = true;
  try {
    if (dk){
      const l = library[dk]; if (!l) return;
      if (l.nut || l.ean || l.gtin || l.nogtin){ const d = {...l}; delete d.rule; delete d.ruleAt; delete d.est; await db.collection(COL).doc(l.id || prodDocId(dk)).set(d); }
      else await db.collection(COL).doc(l.id || prodDocId(dk)).delete();
      memEdit = null; return;
    }
    const base = ent?.raw || {}, store = ent?.store || "";
    const cur = {...base, g: $("mf-g").value.trim(), cat: $("mf-cat").value, bio: $("mf-bio").checked, size: base.unit === "kg" ? "" : $("mf-size").value.trim(), ct: $("mf-ct").value};
    const baseEff = {...base, ct: base.ct || co2Type(base)};
    const ch = ruleChanges(baseEff, cur);
    if (!Object.keys(ch).length){
      const l = library[sk];
      if (!l?.rule){ $("memStatus").textContent = "Nothing changed."; return; }
      const d = {...l}; delete d.rule; delete d.ruleAt; delete d.est;
      if (d.nut || d.ean || d.gtin || d.nogtin) await db.collection(COL).doc(d.id || prodDocId(sk)).set(d); else await db.collection(COL).doc(d.id || prodDocId(sk)).delete();
      memEdit = null; return;
    }
    const prev = library[sk]; if (prev?.rule) library[sk] = {...prev, rule: {}};
    $("memStatus").textContent = ch.cat || ch.g ? "Saving, and refreshing its typical nutrition…" : "Saving…";
    await saveRules([{store, it: {...base, name: ent?.name || base.name}, ch}]);
    memEdit = null; renderAll();
  } catch(_){ const s = $("memStatus"); if (s) s.textContent = "Couldn't save just now. Try again."; }
  finally { if (e.target.isConnected) e.target.disabled = false; }
});
