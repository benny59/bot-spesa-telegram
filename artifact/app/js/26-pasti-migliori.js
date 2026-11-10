"use strict";
// ---------- Meals you cooked: cost × nutrition ----------
const DAY_COL = {wp:"var(--s2)", game:"var(--nsE)", pre:"var(--s2)", strength:"var(--s1)", z2:"var(--s3)", yoga:"var(--s4)", busy:"var(--s5)", weekend:"var(--accent)"};
function renderMeals(){
  const card = $("mealsCard");
  if (!meals.length){ card.innerHTML = `<p class="empty">No meals logged yet. When you cook one of the suggestions, tap “We cooked this”: it's logged here with its cost and nutrition, and its ingredients come out of your kitchen.</p>`; return; }
  const ms = [...meals].sort((a,b)=>b.date.localeCompare(a.date) || String(b.savedAt).localeCompare(String(a.savedAt)));
  const avg = k => ms.reduce((a,m)=>a+(k==="cost"?m.perCost:(m.perAdult?.[k]||0)),0)/ms.length;
  const outItems = cleanReceipts().flatMap(r=>r.items.filter(i=>i.cat==="out"));
  const outAvg = outItems.length ? outItems.reduce((a,i)=>a+i.price,0)/outItems.length : null;
  // scatter: cost per adult portion vs nutrient score, coloured by kind of day
  const W = Math.max(320, Math.min(720, (card.clientWidth || 672) - 32)), H = W < 480 ? 220 : 260, L = 44, Rr = 14, T = 14, B = 32;
  const xs = ms.map(m=>m.perCost), ys = ms.map(m=>m.nrf||0);
  const xhi = Math.max(1, ...xs)*1.15, ylo = Math.min(0, ...ys), yhi = Math.max(100, ...ys)*1.1;
  const X = v => L + v/xhi*(W-L-Rr), Y = v => T + (yhi-v)/(yhi-ylo)*(H-T-B);
  let g = "";
  const xs1 = niceStep(xhi/4); for (let v = 0; v <= xhi; v += xs1){ const x = X(v).toFixed(1); g += `<line x1="${x}" x2="${x}" y1="${T}" y2="${H-B}" stroke="var(--grid)"/><text x="${x}" y="${H-B+14}" text-anchor="middle">${eur(v)}</text>`; }
  const ys1 = niceStep((yhi-ylo)/4); for (let v = Math.ceil(ylo/ys1)*ys1; v <= yhi; v += ys1){ const y = Y(v).toFixed(1); g += `<line x1="${L}" x2="${W-Rr}" y1="${y}" y2="${y}" stroke="var(--grid)"/><text x="${L-6}" y="${(+y+3).toFixed(1)}" text-anchor="end">${Math.round(v)}</text>`; }
  g += `<text x="${(L+W-Rr)/2}" y="${H-4}" text-anchor="middle">cost per adult portion →</text>`;
  ms.forEach(m => { const r = 5 + Math.min(8, (m.perAdult?.p||0)/6);
    g += `<circle cx="${X(m.perCost).toFixed(1)}" cy="${Y(m.nrf||0).toFixed(1)}" r="${r.toFixed(1)}" fill="${DAY_COL[m.day]||"var(--muted)"}" fill-opacity=".85" stroke="var(--surface)"><title>${esc(m.title)}: ${eur(m.perCost)} per adult portion, nutrient score ${Math.round(m.nrf||0)}, ${Math.round(m.perAdult?.p||0)} g protein</title></circle>`;
    g += `<text class="lb" x="${(X(m.perCost)+r+3).toFixed(1)}" y="${(Y(m.nrf||0)+3.5).toFixed(1)}">${esc(m.title.length>20?m.title.slice(0,19)+"…":m.title)}</text>`; });
  const daysUsed = [...new Set(ms.map(m=>m.day))];
  card.innerHTML = `<div class="ntiles">
      <div class="stat"><div class="k">Meals logged</div><div class="v num">${ms.length}</div><div class="s">${ms.filter(m=>days(m.date,todayISO())<7).length} in the last 7 days</div></div>
      <div class="stat"><div class="k">Per adult portion</div><div class="v num">${eur(avg("cost"))}</div><div class="s">${outAvg ? `a café item cost you ${eur(outAvg)} on average` : "average cost"}</div></div>
      <div class="stat"><div class="k">Protein</div><div class="v num">${Math.round(avg("p"))} g</div><div class="s">per adult portion</div></div>
      <div class="stat"><div class="k">Energy</div><div class="v num">${fmtInt(avg("kcal"))}</div><div class="s">kcal per adult portion</div></div></div>
    <div class="tbl-wrap" style="margin-top:12px"><svg class="scat" viewBox="0 0 ${W} ${H}" role="img" aria-label="Meals by cost per portion and nutrient score">${g}</svg></div>
    <div class="legend">${daysUsed.map(k=>`<span><i class="sw" style="background:${DAY_COL[k]||"var(--muted)"}"></i>${esc((DAYS.find(d=>d.k===k)||{n:k}).n)}</span>`).join("")}<span>dot size = protein</span></div>
    <div class="mlist" style="margin-top:10px">${ms.map(m=>`<div class="ml"><div>${esc(m.title)}<small>${esc(weekday(m.date))} ${esc(fmtDay(m.date))} · ${esc((DAYS.find(d=>d.k===m.day)||{n:""}).n)} · ${esc((MEALS.find(x=>x.k===m.meal)||{n:""}).n)} · ${m.portions} portions</small></div>
      <div class="num" style="text-align:right">${eur(m.perCost)}<small>${fmtInt(m.perAdult?.kcal||0)} kcal · ${Math.round(m.perAdult?.p||0)} g protein${m.perAdult?.co2 ? ` · ${fmtInt(m.perAdult.co2)} g CO₂e` : ""}</small></div>
      <button type="button" data-mdel="${esc(m.id)}" id="mdel-${esc(m.id)}" style="padding:6px 10px;font-size:12px">Delete</button></div>`).join("")}</div>
    <p class="note" style="margin-top:8px">Deleting a meal puts its ingredients back in your kitchen.</p>`;
}
$("mealsCard").addEventListener("click", async e => {
  const id = e.target.dataset?.mdel; if (!id) return; const b = e.target;
  if (b.dataset.armed !== "1"){ b.dataset.armed = "1"; b.textContent = "Tap again"; setTimeout(()=>{ if (b.isConnected){ b.dataset.armed=""; b.textContent="Delete"; } }, 4000); return; }
  if (db && uid){ try { await db.collection(COL).doc(id).delete(); } catch(_){ b.textContent = "Couldn't delete"; } }
  else { meals = meals.filter(m=>m.id!==id); renderAll(); }
});

// =====================================================================
// Nutrition: most nutritious foods you've ever bought
// =====================================================================
let bestMode = "kcal";
function aggregateAll(){
  const out = {};
  for (const r of cleanReceipts()) r.items.forEach(it0 => {
    const it = withLib(r, it0); if (!isFood(it)) return;
    const ln = lineNutrition(it); if (!ln) return;
    const key = (it.g || it.name).toLowerCase().trim() + (it.bio ? "|bio" : "");
    const P = (out[key] ||= {key, name: it.g || it.name, bio: !!it.bio, cat: it.cat, spend: 0, kg: 0, n: 0, last: "", ns: nsOf(it)?.grade || "", mic: {}, ...Object.fromEntries(NUT.map(n=>[n.k,0]))});
    P.spend += it.price; P.kg += ln.kg; P.n++; if (r.date > P.last) P.last = r.date;
    for (const n of NUT) P[n.k] += ln[n.k];
    if (ln.mic) for (const m of MIC) P.mic[m.k] = (P.mic[m.k]||0) + ln.mic[m.k];
  });
  return Object.values(out);
}
function renderBest(){
  const card = $("nutBest");
  const all = aggregateAll().filter(p => p.kg >= 0.1 && p.kcal >= 150);
  if (all.length < 3){ card.hidden = true; return; }
  card.hidden = false;
  const val = p => bestMode === "g" ? nrfOf(p, "g") : bestMode === "eur" ? (nrfOf(p)||0)*(p.kcal/100)/p.spend/100 : nrfOf(p);
  const list = all.map(p => ({...p, v: val(p)})).filter(p => p.v > 0).sort((a,b)=>b.v-a.v).slice(0, 15);
  const vmax = Math.max(...list.map(p=>p.v));
  const unit = bestMode === "eur" ? " pts/€" : "";
  card.innerHTML = `<div class="row" style="justify-content:space-between;margin-bottom:10px"><h3>Most nutritious foods you've bought</h3>
      <div class="chips" id="bestMode" role="group" aria-label="Ranked by">${[["kcal","Per calorie"],["g","Per 100 g"],["eur","Per euro"]].map(([k,n])=>`<button type="button" id="bm-${k}" data-bm="${k}" aria-pressed="${k===bestMode}">${n}</button>`).join("")}</div></div>
    <div class="vlist" style="max-height:none">${list.map((p,i)=>`<div class="vrow" style="grid-template-columns:minmax(0,12em) 1fr 4.5em auto"><div class="nm" title="${esc(p.name)}">${i+1}. ${p.ns?`<span class="ns ${p.ns}" style="margin:0 5px 0 0">${p.ns}</span>`:""}${esc(p.name)}${p.bio?" ·bio":""}<small>${eur(p.spend/p.kg)}/kg · bought ${p.n}× · last ${esc(fmtDay(p.last))}</small></div>
      <div><div class="bar" style="width:${(p.v/vmax*100).toFixed(1)}%;background:var(--down)"></div></div><div class="v">${p.v>=100?fmtInt(p.v):p.v.toLocaleString("de-DE",{maximumFractionDigits:1})}${unit}</div>
      <button type="button" data-cookwith="${esc(p.key)}" style="padding:5px 9px;font-size:12px">Cook with it</button></div>`).join("")}</div>
    <p class="note" style="margin-top:8px">Ranked by the nutrient score ${bestMode==="g"?"per 100 g":bestMode==="eur"?"per euro (nutrients per euro, after Drewnowski)":"per 100 kcal"} across every receipt; products bought in tiny amounts (spices) are left out. “Cook with it” adds the product to the next recipe suggestions.</p>`;
}
$("nutBest").addEventListener("click", e => {
  const b = e.target.closest("button[data-bm]"); if (b){ bestMode = b.dataset.bm; renderBest(); return; }
  const k = e.target.dataset?.cookwith; if (k){ pins.add(k); showView("recipes", {focus:"suggestBtn"}); }
});
