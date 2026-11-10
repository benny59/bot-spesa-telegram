"use strict";
// ---------- Render: same product, different shops ----------
function storeColors(){
  const counts = {}; for (const r of cleanReceipts()){ const c = chainOf(r.store); counts[c] = (counts[c]||0)+1; }
  const keys = Object.keys(counts).sort((a,b)=>counts[b]-counts[a]);
  const out = {}; keys.forEach((k,i)=>out[k] = `var(--s${(i%5)+1})`); return out;
}
function renderCompare(){
  const card = $("cmpCard");
  const groups = {};
  for (const r of [...cleanReceipts()].sort((a,b)=>a.date.localeCompare(b.date))){
    const ch = chainOf(r.store);
    for (const it of r.items){
      if (!isFood(it) || isSlip(it) || !it.g || !(it.price>0)) continue;
      const cp = compPrice(it), ean = eanDi(library[itemKey(r.store, it)]), gk = (ean ? "ean:" + ean : genKey(it)) + "|" + cp.u;   // con il codice il prodotto è lo stesso anche se i nomi differiscono
      const g = (groups[gk] ||= {g:it.g, u:cp.u, bio:new Set(), stores:{}});
      g.bio.add(!!it.bio);
      const s = (g.stores[ch] ||= {label:chainLabel(r.store), prices:[], last:null, names:new Set()});
      s.prices.push(cp.p); s.last = {p:cp.p, date:r.date, bio:!!it.bio}; s.names.add(it.name);
    }
  }
  const multi = Object.values(groups).filter(g => Object.keys(g.stores).length >= 2);
  if (!multi.length){
    card.innerHTML = `<p class="empty">Nothing you've bought so far appears in more than one shop${mergeOrganic ? "" : " as the same organic or conventional product"}. As soon as it does, each shop's price per kg, litre or piece appears here side by side.${mergeOrganic ? "" : " Ticking “Count organic and conventional as one product” widens the comparison."}</p>`;
    return;
  }
  const colors = storeColors();
  multi.forEach(g => { const ps = Object.values(g.stores).map(s=>s.last.p); g.min = Math.min(...ps); g.max = Math.max(...ps); g.spread = g.max/g.min - 1; });
  multi.sort((a,b) => (a.u==="pack") - (b.u==="pack") || b.spread - a.spread);
  // Store price level: average log gap to each product's geometric mean, sized products only.
  const lvl = {}, sized = multi.filter(g=>g.u!=="pack");
  for (const g of sized){
    const ent = Object.entries(g.stores), gm = ent.reduce((a,[,s])=>a+Math.log(s.last.p),0)/ent.length;
    for (const [ch,s] of ent){ (lvl[ch] ||= {label:s.label, sum:0, n:0}); lvl[ch].sum += Math.log(s.last.p) - gm; lvl[ch].n++; }
  }
  const cheapest = {}; for (const g of sized){ const [ch] = Object.entries(g.stores).sort((a,b)=>a[1].last.p-b[1].last.p)[0]; cheapest[ch] = (cheapest[ch]||0)+1; }
  const lvlRows = Object.entries(lvl).filter(([,v])=>v.n>=1).sort((a,b)=>a[1].sum/a[1].n-b[1].sum/b[1].n);
  const head = sized.length ? `<div class="levels">${lvlRows.map(([ch,v])=>`<div><span class="sw" style="background:${colors[ch]}"></span>${esc(v.label)} <b class="num ${cls(v.sum/v.n*100)}">${pct((Math.exp(v.sum/v.n)-1)*100,0)}</b> <span class="status">vs the average of your shops · ${v.n} product${v.n>1?"s":""}${cheapest[ch]?` · cheapest on ${cheapest[ch]}`:""}</span></div>`).join("")}</div>
    <p class="note" style="margin:6px 0 4px">${sized.length < 5 ? `Based on only ${sized.length} shared product${sized.length>1?"s":""} so far, so read it as a first hint.` : `Based on ${sized.length} products you've bought in more than one shop.`} Latest price in each shop.</p>` : "";
  const rows = multi.map(g => {
    const ent = Object.entries(g.stores).sort((a,b)=>a[1].last.p-b[1].last.p);
    const top = g.max * 1.08, x = v => (v/top*100);
    const allP = ent.flatMap(([,s])=>s.prices);
    const bioTxt = mergeOrganic ? (g.bio.size>1 ? "organic & conventional" : [...g.bio][0] ? "organic" : "conventional") : ([...g.bio][0] ? "organic" : "conventional");
    const dots = ent.map(([ch,s],i) => {
      const xp = x(s.last.p).toFixed(1);
      const title = `${s.label}: ${fmtUP(s.last.p,g.u)} on ${fmtDay(s.last.date)}${mergeOrganic ? (s.last.bio ? ", organic" : ", conventional") : ""} (${[...s.names].join(", ")})`;
      return `<span class="dot${g.u==="pack"?" unsized":""}" style="left:${xp}%;background:${colors[ch]}" title="${esc(title)}"></span>
        <span class="dot-lab ${i%2?"bot":"top"}${i===0&&ent.length>1&&g.spread>0.005?" best":""}" style="left:${xp}%"><span class="st">${esc(s.label)}${mergeOrganic&&s.last.bio?"·bio":""}</span> ${fmtUP(s.last.p,g.u)}</span>`;
    }).join("");
    const lo = Math.min(...allP), hi = Math.max(...allP);
    return `<div class="cmp-row"><div class="cmp-name">${esc(g.g)}<small>${unitLabel(g.u)} · ${bioTxt}${g.u==="pack"?" · pack sizes not known yet":` · ${g.spread>0.005?`${pct(g.spread*100,0)} between cheapest and dearest`:"same price"}`}</small></div>
      <div class="cmp-track"><span class="axis"></span><span class="range" style="left:${x(lo).toFixed(1)}%;width:${(x(hi)-x(lo)).toFixed(1)}%"></span>${dots}</div></div>`;
  }).join("");
  card.innerHTML = head + `<div class="cmp">${rows}</div>
    <p class="note" style="margin-top:8px">Prices are compared per kg, litre or piece, so different pack sizes line up. Where a pack size isn't known the dots are faded and show the pack price; add the size with Edit under Saved receipts. The grey bar spans every price you've paid for the product.</p>`;
}
$("mergeBio").addEventListener("change", e => {
  mergeOrganic = e.target.checked;
  try { localStorage.setItem("bi-merge", mergeOrganic ? "1" : ""); } catch(_){}
  renderCompare(); renderTrack();
});
