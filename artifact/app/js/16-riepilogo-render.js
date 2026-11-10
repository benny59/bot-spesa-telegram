"use strict";
// ---------- Render: official-rate summary ----------
function renderSummary(){
  const {list,label} = activeBasket(); const eff = effective(); const b = basketFrom(list, eff); const o = eff.o;
  $("youDE").textContent = b.total ? pct(b.de) : "–";
  const nonfood = list.reduce((a,r)=>a+r.items.filter(i=>i.cat==="nonfood").reduce((x,i)=>x+i.price,0),0);
  const outSp = list.reduce((a,r)=>a+r.items.filter(i=>i.cat==="out").reduce((x,i)=>x+i.price,0),0);
  $("heroMeta").textContent = b.total ? `${eur(b.total)} of food weighted across ${b.rows.length} HICP classes${nonfood>0?` · ${eur(nonfood)} non-food`:""}${outSp>0?` · ${eur(outSp)} cafés & eating out`:""} left out` : "Add a receipt to start";
  $("basketLabel").textContent = label;
  const items = [
    {lab:"You, at German rates", sub:"your weights × DE class rates", v:b.de, col:"var(--accent)"},
    {lab:"Germany · food", sub:"official, Destatis", v:o.de.food, col:"var(--de)"},
    {lab:"Germany · HICP", sub:"all items incl. energy", v:o.de.hicp, col:"var(--de)", op:.55},
    {gap:true},
    {lab:"You, at euro-area rates", sub:"your weights × processed/unprocessed", v:b.ea, col:"var(--accent)", op:.7},
    {lab:"Euro area · food, alc. & tob.", sub:"official, Eurostat", v:o.ea.fat, col:"var(--ea)"},
    {lab:"Euro area · HICP", sub:"all items incl. energy", v:o.ea.hicp, col:"var(--ea)", op:.55},
  ];
  const vals = items.filter(i=>!i.gap).map(i=>i.v);
  const lo = Math.min(0, ...vals), hi = Math.max(0, ...vals), span = (hi-lo)||1;
  const x = v => (v-lo)/span*100;
  $("bars").innerHTML = items.map(i => i.gap ? '<div class="group-gap"></div>' : `
    <div class="bar"><div class="lab">${esc(i.lab)}<small>${esc(i.sub)}</small></div>
      <div class="track"><div class="fill" style="left:${Math.min(x(0),x(i.v))}%;width:${Math.abs(x(i.v)-x(0))}%;background:${i.col};opacity:${i.op||1}"></div><div class="zero" style="left:${x(0)}%"></div></div>
      <div class="val num">${pct(i.v)}</div></div>`).join("");
  $("period").textContent = `Annual rates for ${o.label}, the latest month published. This figure applies official price changes to your spending mix across all saved receipts. Your own shelf prices are tracked in the index above.`;
  $("catTable").innerHTML = `<thead><tr><th>Class</th><th class="r">Spent</th><th class="r">Share</th><th class="r">DE rate</th><th class="r">EA</th><th class="r">Contrib.</th></tr></thead><tbody>${
    b.rows.map(r => `<tr><td>${esc(r.c.n)} <span class="note num">${r.c.coicop}</span> ${r.fb ? '<span class="chip fb">aggr.</span>':''}</td>
      <td class="r num">${eur(r.s)}</td><td class="r num">${(r.w*100).toFixed(1)}%</td>
      <td class="r num ${cls(r.r)}">${pct(r.r)}</td>
      <td class="r num">${r.c.ea==="unproc"?"unproc.":r.c.ea==="hicp"?"HICP":"proc."}</td>
      <td class="r num ${cls(r.contrib)}">${(r.contrib>=0?"+":"−")+Math.abs(r.contrib).toFixed(2)} pp</td></tr>`).join("")
  }</tbody><tfoot><tr><td><b>Your rate</b></td><td class="r num"><b>${eur(b.total)}</b></td><td class="r num">100%</td><td></td><td></td><td class="r num"><b>${pct(b.de,2)}</b></td></tr></tfoot>`;
}

function catSelect(it, idx){
  const opts = CATS.map(c => `<option value="${c.k}"${it.cat===c.k?" selected":""}>${esc(c.n)}</option>`).join("")
    + `<option value="${EXCLUDED}"${it.cat===EXCLUDED?" selected":""}>Not counted (deposit, bag)</option>`;
  return `<select id="cat-${idx}" data-i="${idx}" aria-label="Class for ${esc(it.name)}">${opts}</select>`;
}
function wtHint(it){
  const wu = weightPerUnit(it); if (!wu || it.unit === "kg") return "";
  const g = wu.w*1000*(it.qty||1);
  return `<span class="wt">${g >= 1000 ? (g/1000).toLocaleString("de-DE",{maximumFractionDigits:2})+" kg" : Math.round(g)+" g"}${wu.src==="est"?" est.":""}${it.nut?` · ${Math.round(it.nut.kcal)} kcal/100 g ${isLabelled(it)?"(label)":"(typical)"}`:""}</span>`;
}
function renderDraft(){
  const sec = $("draftSec");
  if (!draft){ sec.hidden = true; return; }
  sec.hidden = false;
  $("draftBanner").hidden = !draftIsExample;
  $("draftBanner").textContent = "This is the receipt you sent in chat, already read and sorted. Check the classes, then save it.";
  $("draftTitle").textContent = editingId ? "Correct a saved receipt" : draftIsExample ? "Your 21 Oct receipt" : "Check the items";
  $("saveBtn").textContent = editingId ? "Save changes" : "Save receipt";
  $("discardBtn").textContent = editingId ? "Cancel" : "Discard";
  $("dStore").value = draft.store || ""; $("dDate").value = draft.date || "";
  const sum = draft.items.reduce((a,i)=>a+i.price,0);
  const diff = draft.total ? Math.abs(sum-draft.total) : 0;
  $("dTotal").innerHTML = `Lines ${eur(sum)}${draft.total? ` · receipt ${eur(draft.total)}` : ""}${diff>0.02?` <span class="up">· ${eur(diff)} off, check a line</span>`:" ✓"}`;
  $("draftTable").innerHTML = `<thead><tr><th>Item</th><th class="r">Qty</th><th class="r">Price</th><th>HICP class</th></tr></thead><tbody>${
    draft.items.map((it,i)=>`<tr class="${it.cat===EXCLUDED?'excluded':''}"><td>${esc(it.name)} <span class="note num">${esc(it.code||"")}</span> ${favChip(it)}${isFood(it)?`<div class="gen">
        <input type="text" class="g" id="g-${i}" data-g="${i}" value="${esc(it.g||"")}" placeholder="Compare as…" aria-label="Generic product for ${esc(it.name)}">
        <input type="text" class="sz" id="sz-${i}" data-sz="${i}" value="${esc(it.size||"")}" placeholder="${it.unit==="kg"?"by weight":"size"}" ${it.unit==="kg"?"disabled":""} aria-label="Pack size for ${esc(it.name)}">
        <label for="bio-${i}"><input type="checkbox" id="bio-${i}" data-bio="${i}" ${it.bio?"checked":""}>organic</label>${wtHint(it)}${it._rule?' <span class="chip mem-rule">your rule</span>':it._mem?' <span class="chip fb">remembered</span>':""}</div>`:""}</td>
      <td class="r num">${it.unit==="kg"? it.qty.toFixed(3)+" kg" : it.qty}</td><td class="r"><input class="price num" type="number" step="0.01" id="price-${i}" data-p="${i}" value="${it.price}" aria-label="Price of ${esc(it.name)}"></td><td>${catSelect(it,i)}</td></tr>`).join("")
  }</tbody>`;
}

function renderRepeats(){
  const box = $("tracker");
  const obs = {};
  for (const r of sortedReceipts()) for (const it of r.items){
    if (!isFood(it) || isSlip(it) || !(it.qty>0)) continue;
    const k = itemKey(r.store,it); const up = unitPriceOf(it);
    const o = (obs[k] ||= {name:it.name, unit:it.unit, store:chainLabel(r.store), pts:[]});
    const lastPt = o.pts[o.pts.length-1];
    if (lastPt && lastPt.rid === r.id) continue;
    o.pts.push({date:r.date, up, rid:r.id});
  }
  const rows = Object.values(obs).filter(o=>o.pts.length>1).map(o => {
    const f = o.pts[0], l = o.pts[o.pts.length-1];
    return {name:o.name, store:o.store, unit:o.unit, n:o.pts.length, f, l, ch:(l.up/f.up-1)*100};
  }).sort((a,b)=>b.n-a.n || Math.abs(b.ch)-Math.abs(a.ch));
  if (!rows.length){
    box.innerHTML = `<p class="empty">Products you buy on more than one receipt appear here, with the first price you paid and the latest.</p>`;
    return;
  }
  box.innerHTML = `<div class="tbl-wrap"><table><thead><tr><th>Product</th><th class="r">Bought</th><th class="r">First</th><th class="r">Latest</th><th class="r">Change</th></tr></thead><tbody>${
    rows.map(r=>`<tr><td>${esc(r.name)}<div class="note">${esc(r.store)}</div></td><td class="r num">${r.n}×</td><td class="r num">${eur(r.f.up)}${r.unit==="kg"?"/kg":""}<div class="note">${esc(fmtDay(r.f.date))}</div></td><td class="r num">${eur(r.l.up)}${r.unit==="kg"?"/kg":""}<div class="note">${esc(fmtDay(r.l.date))}</div></td><td class="r num ${cls(r.ch)}">${pct(r.ch)}</td></tr>`).join("")
  }</tbody></table></div>`;
}

function renderHistory(){
  const box = $("history");
  if ((!db || !uid) && !receipts.length){ box.innerHTML = `<p class="empty">Saving needs you signed in to Claude. Without it, the page still reads and analyses a receipt but forgets it on reload.</p>`; return; }
  if (!receipts.length){ box.innerHTML = `<p class="empty">${loaded ? "No receipts saved yet. Save the one above, then add one after each shop." : "Loading…"}</p>`; return; }
  const dups = dupIds();
  const sorted = [...receipts].sort((a,b)=> b.date.localeCompare(a.date) || String(b.savedAt).localeCompare(String(a.savedAt)));
  const head = dups.size ? `<p class="banner" style="margin:0 0 8px">${dups.size} receipt${dups.size>1?"s are":" is"} saved twice and left out of every figure. Delete the copy marked “duplicate” to tidy up.</p>` : "";
  const mostrati = histAll ? sorted : sorted.slice(0, 3);
  box.innerHTML = head + mostrati.map(r => {
    const food = r.items.filter(isFood).reduce((a,i)=>a+i.price,0);
    const other = r.items.filter(i=>i.cat==="nonfood"||i.cat==="out").reduce((a,i)=>a+i.price,0);
    return `<div class="hist-item"><div><div style="font-weight:600">${esc(r.store||"Receipt")} ${dups.has(r.id)?'<span class="chip dup">duplicate</span>':''}</div><div class="status num">${esc(r.date)} · ${r.items.length} lines · ${eur(food)} food${other>0?` · ${eur(other)} non-food`:""}</div></div>
      <div class="row"><button data-edit="${esc(r.id)}" id="edit-${esc(r.id)}">Edit</button><button data-del="${esc(r.id)}" id="del-${esc(r.id)}">Delete</button></div></div>`;
  }).join("") + (sorted.length > 3 ? `<button type="button" id="histMore" style="margin-top:8px">${esc(histAll ? t("hist.less") : t("hist.more", {n: sorted.length}))}</button>` : "");
}
$("history").addEventListener("click", e => { if (e.target.id === "histMore"){ histAll = !histAll; renderHistory(); } });

function renderRates(){
  const eff = effective(); const o = eff.o;
  $("ratesNote").textContent = `German class rates are the consumer price index subgroups from Destatis, which the HICP subindices track closely; euro-area figures are from Eurostat. Latest release in use: ${o.label}${o.source ? " (" + o.source + ")" : ""}.`;
  const ks = monthKeys().reverse();
  $("monthsTable").innerHTML = `<thead><tr><th>Month</th><th class="r">DE HICP</th><th class="r">DE food</th><th class="r">EA HICP</th><th class="r">EA food, alc. & tob.</th></tr></thead><tbody>${
    ks.map(k=>{ const m = official[k]; return `<tr><td>${esc(m.label||fmtMonth(k))}</td><td class="r num">${pct(m.de.hicp)}</td><td class="r num">${pct(m.de.food)}</td><td class="r num">${pct(m.ea.hicp)}</td><td class="r num">${pct(m.ea.fat)}</td></tr>`; }).join("")
  }</tbody>`;
  $("ratesHead").textContent = `Class rates, ${o.label}`;
  $("ratesTable").innerHTML = `<thead><tr><th>Class</th><th class="r">Annual %</th></tr></thead><tbody>${
    CATS.filter(c=>c.k!=="nonfood").map(c=>`<tr><td>${esc(c.n)} ${eff.cr[c.k].fb?'<span class="chip fb">aggr.</span>':''}</td><td class="r"><input type="number" step="0.1" id="rate-${c.k}" data-k="${c.k}" value="${eff.r[c.k]}"></td></tr>`).join("")
  }<tr><td>Euro area · processed food, alc. & tob.</td><td class="r"><input type="number" step="0.1" id="rate-eaProc" data-k="eaProc" value="${eff.r.eaProc}"></td></tr>
   <tr><td>Euro area · unprocessed food</td><td class="r"><input type="number" step="0.1" id="rate-eaUnproc" data-k="eaUnproc" value="${eff.r.eaUnproc}"></td></tr></tbody>`;
}
function renderAll(){ renderTrack(); renderCompare(); renderNutrition(); renderBest(); renderSummary(); renderDraft(); renderRepeats(); renderHistory(); renderPlan(); renderPantry(); renderRecipes(); renderMeals(); renderGlance(); renderMemory(); renderWeek(); }
