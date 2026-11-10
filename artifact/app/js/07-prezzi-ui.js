"use strict";
// ---------- Render: tracker ----------
function renderStoreChips(){
  const box = $("storeChips");
  const counts = {}; const labels = {};
  for (const r of cleanReceipts()){ const c = chainOf(r.store); counts[c] = (counts[c]||0)+1; labels[c] ||= chainLabel(r.store); }
  const keys = Object.keys(counts).sort((a,b)=>counts[b]-counts[a]);
  if (keys.length < 2 || matchMode === "any"){ box.hidden = true; if (storeFilter!=="all" && !counts[storeFilter]) storeFilter = "all"; return; }
  if (storeFilter!=="all" && !counts[storeFilter]) storeFilter = "all";
  box.hidden = false;
  box.innerHTML = [["all","All stores",cleanReceipts().length], ...keys.map(k=>[k,labels[k],counts[k]])]
    .map(([k,l,n]) => `<button type="button" id="store-${esc(k)}" data-store="${esc(k)}" aria-pressed="${storeFilter===k}">${esc(l)} <span class="num">${n}</span></button>`).join("");
}
$("storeChips").addEventListener("click", e => {
  const b = e.target.closest("button[data-store]"); if (!b) return;
  storeFilter = b.dataset.store; selected = null;
  try { localStorage.setItem("bi-store", storeFilter); } catch(_){}
  renderStoreChips(); renderTrack(); renderRepeats();
});
function renderBreadth(pts){
  const box = $("breadth");
  const all = pts.flatMap(p=>p.matched);
  if (!all.length){ box.hidden = true; return; }
  let up = 0, down = 0, same = 0;
  for (const m of all){ if (m.rel > 1.005) up++; else if (m.rel < 0.995) down++; else same++; }
  const n = all.length, w = v => (v/n*100).toFixed(1)+"%";
  box.hidden = false;
  box.innerHTML = `<div class="strip" role="img" aria-label="${same} same price, ${up} dearer, ${down} cheaper">
      <span style="width:${w(same)};background:var(--muted);opacity:.45"></span><span style="width:${w(up)};background:var(--up)"></span><span style="width:${w(down)};background:var(--down)"></span></div>
    <div class="keys"><span>Of <b>${n}</b> repeat purchases:</span>
      <span><i class="sw" style="background:var(--muted);opacity:.45"></i><b>${same}</b> same price</span>
      <span><i class="sw" style="background:var(--up)"></i><b>${up}</b> dearer</span>
      <span><i class="sw" style="background:var(--down)"></i><b>${down}</b> cheaper</span></div>`;
}
function driverText(pts){
  const total = Math.log(pts[pts.length-1].I/100), d = pts.drivers || [];
  if (!d.length || Math.abs(total) < 1e-6) return "";
  const share = d[0].ln/total;
  if (share < 0.4) return "";
  return `<br>${esc(d[0].name)} alone accounts for ${pct((Math.exp(d[0].ln)-1)*100)}`;
}
function renderMode(){
  $("modeSame").setAttribute("aria-pressed", matchMode==="same"); $("modeAny").setAttribute("aria-pressed", matchMode==="any");
  $("modeNote").textContent = matchMode === "same"
    ? "Each product is compared only with itself in the same chain, as official statistics do. Switching shop doesn't count as a price change."
    : "Products are compared with the same kind of product bought anywhere, per kg, litre or piece. Buying apple juice at ALDI after Scheck-In shows up as a saving: this tracks what your groceries actually cost you." + (mergeOrganic ? " Organic and conventional count as one product." : "");
}
document.querySelector(".seg").addEventListener("click", e => {
  const b = e.target.closest("button[data-mode]"); if (!b) return;
  matchMode = b.dataset.mode; selected = null;
  try { localStorage.setItem("bi-mode", matchMode); } catch(_){}
  renderTrack();
});
function renderTrack(){
  renderMode();
  renderStoreChips();
  const pts = chain();
  const stats = $("trackStats"), box = $("chartBox");
  if (!pts.length){
    $("trackSpan").textContent = "";
    stats.innerHTML = "";
    box.innerHTML = `<p class="empty">${loaded || !db ? "Save your first receipt and the index starts at 100. Each later receipt with products you bought before moves it, and the chart fills in here." : "Loading your receipts…"}</p>`;
    $("legend").innerHTML = ""; $("detail").hidden = true; $("monthBox").hidden = true; $("breadth").hidden = true;
    return;
  }
  const first = pts[0], lastP = pts[pts.length-1];
  const span = days(first.date, lastP.date);
  const change = lastP.I/100 - 1;
  const nMatchedReceipts = pts.filter(p=>p.matched.length).length;
  const products = new Set(pts.flatMap(p=>p.matched.map(m=>m.name))).size;
  const later = pts.slice(1), laterFood = later.reduce((a,p)=>a+p.food,0);
  const avgCover = laterFood ? later.reduce((a,p)=>a+p.cover*p.food,0)/laterFood : 0;
  $("trackSpan").textContent = `${storeFilter==="all" || matchMode==="any" ? "" : chainLabel(storeFilter)+" · "}${pts.length} receipt${pts.length>1?"s":""} · ${fmtDay(first.date)} – ${fmtDay(lastP.date)} ${lastP.date.slice(0,4)}`;
  // annualised / year-on-year
  let rateV = "–", rateS = "";
  const yearAgo = [...pts].reverse().find(p => days(p.date, lastP.date) >= 335);
  if (yearAgo){ rateV = pct((lastP.I/yearAgo.I - 1)*100); rateS = `year on year, vs ${fmtDay(yearAgo.date)} ${yearAgo.date.slice(0,4)}`; }
  else if (span >= 90){ rateV = pct((Math.pow(lastP.I/100, 365/span) - 1)*100); rateS = `annualised over ${span} days`; }
  else { rateS = span < 1 ? "needs receipts on more than one day" : `after ${90-span} more days of receipts (3 months)`; }
  stats.innerHTML = `
    <div class="stat lead"><div class="k">Since ${fmtDay(first.date)}</div><div class="v num">${pts.length>1 ? pct(change*100) : "±0.0 %"}</div><div class="s">index ${lastP.I.toFixed(1)} (start = 100)${driverText(pts)}</div></div>
    <div class="stat"><div class="k">Yearly rate</div><div class="v num">${rateV}</div><div class="s">${esc(rateS)}</div></div>
    <div class="stat"><div class="k">Evidence</div><div class="v num">${products}</div><div class="s">repeat product${products===1?"":"s"} over ${nMatchedReceipts} receipt${nMatchedReceipts===1?"":"s"}${pts.length>1?` · ${Math.round(avgCover*100)} % of later spending matched`:""}</div></div>`;
  renderBreadth(pts);
  box.innerHTML = chartSVG(pts);
  const latestO = latestOfficial();
  $("legend").innerHTML = `<span><i style="border-color:var(--accent)"></i>Your shelf prices</span>
    <span><i class="dash" style="border-color:var(--de)"></i>Germany food, official pace (${pct(latestO.de.food)} in ${esc(latestO.label)})</span>
    <span><i class="dash" style="border-color:var(--ea)"></i>Euro area food, alc. & tob. (${pct(latestO.ea.fat)})</span>`;
  box.querySelectorAll(".pt").forEach(g => {
    const pick = () => { selected = g.dataset.id; renderTrack(); };
    g.addEventListener("click", pick);
    g.addEventListener("keydown", e => { if (e.key==="Enter"||e.key===" "){ e.preventDefault(); pick(); } });
  });
  if (!selected || !pts.find(p=>p.id===selected)) selected = (pts.slice().reverse().find(p=>p.matched.length) || lastP).id;
  renderDetail(pts.find(p=>p.id===selected));
  renderMonths(pts);
}

function chartSVG(pts){
  const cw = Math.round($("chartBox").clientWidth || 640);
  const W = Math.max(300, Math.min(720, cw)), H = W < 480 ? 210 : 250, L = 40, R = 12, T = 14, B = 30;
  const t0 = d2(pts[0].date), tEnd = d2(pts[pts.length-1].date);
  const minSpan = 30*864e5;
  const t1 = new Date(Math.max(+tEnd, +t0 + minSpan));
  const endDate = t1.toISOString().slice(0,10);
  // reference series sampled weekly
  const refs = [];
  for (let t = +t0; ; t += 7*864e5){
    const ds = new Date(Math.min(t, +t1)).toISOString().slice(0,10);
    refs.push({date:ds, de:paceIndex(pts[0].date, ds, o=>o.de.food), ea:paceIndex(pts[0].date, ds, o=>o.ea.fat)});
    if (t >= +t1) break;
  }
  const vals = [100, ...pts.map(p=>p.I), ...refs.flatMap(r=>[r.de, r.ea])];
  let lo = Math.min(...vals), hi = Math.max(...vals);
  const pad = Math.max(1.5, (hi-lo)*0.12); lo -= pad; hi += pad;
  const step = niceStep((hi-lo)/4);
  lo = Math.floor(lo/step)*step; hi = Math.ceil(hi/step)*step;
  const x = ds => L + (d2(ds)-t0)/(t1-t0) * (W-L-R);
  const y = v => T + (hi-v)/(hi-lo) * (H-T-B);
  let g = "";
  for (let v = lo; v <= hi + 1e-9; v += step){
    const yy = y(v).toFixed(1);
    g += `<line x1="${L}" x2="${W-R}" y1="${yy}" y2="${yy}" stroke="var(${Math.abs(v-100)<1e-9?"--muted":"--grid"})" stroke-width="1" ${Math.abs(v-100)<1e-9?'stroke-dasharray="2 3"':''}/>`;
    g += `<text x="${L-6}" y="${(+yy+4).toFixed(1)}" text-anchor="end">${fmtNum(v, step)}</text>`;
  }
  // x ticks: month starts, or weekly if short
  const totalDays = (t1-t0)/864e5;
  const ticks = [];
  if (totalDays <= 75){ for (let t = +t0; t <= +t1; t += 7*864e5) ticks.push(new Date(t).toISOString().slice(0,10)); }
  else { let d = new Date(Date.UTC(t0.getUTCFullYear(), t0.getUTCMonth()+1, 1)); const every = totalDays > 400 ? 3 : 1;
    let i = 0; while (d <= t1){ if (i++ % every === 0) ticks.push(d.toISOString().slice(0,10)); d = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth()+1, 1)); } }
  for (const ds of ticks){
    const xx = x(ds).toFixed(1);
    g += `<line x1="${xx}" x2="${xx}" y1="${H-B}" y2="${H-B+4}" stroke="var(--muted)"/>`;
    g += `<text x="${xx}" y="${H-B+17}" text-anchor="middle">${totalDays<=75 ? fmtDay(ds) : MONTHS_EN[d2(ds).getUTCMonth()]+(d2(ds).getUTCMonth()===0?" "+ds.slice(2,4):"")}</text>`;
  }
  const path = arr => arr.map((p,i)=>(i?"L":"M")+x(p[0]).toFixed(1)+" "+y(p[1]).toFixed(1)).join(" ");
  g += `<path d="${path(refs.map(r=>[r.date,r.de]))}" fill="none" stroke="var(--de)" stroke-width="1.5" stroke-dasharray="5 4"/>`;
  g += `<path d="${path(refs.map(r=>[r.date,r.ea]))}" fill="none" stroke="var(--ea)" stroke-width="1.5" stroke-dasharray="5 4"/>`;
  // your index: step-after line (holds level until the next receipt), area to 100
  const sp = [];
  pts.forEach((p,i) => { if (i) sp.push([p.date, pts[i-1].I]); sp.push([p.date, p.I]); });
  if (endDate > pts[pts.length-1].date) sp.push([pts[pts.length-1].date, pts[pts.length-1].I]);
  const area = path(sp) + ` L${x(pts[pts.length-1].date).toFixed(1)} ${y(100).toFixed(1)} L${x(pts[0].date).toFixed(1)} ${y(100).toFixed(1)} Z`;
  g += `<path d="${area}" fill="var(--accent)" opacity=".08"/>`;
  g += `<path d="${path(sp)}" fill="none" stroke="var(--accent)" stroke-width="2.25" stroke-linejoin="round"/>`;
  pts.forEach((p,i) => {
    const r = p.matched.length ? 3.5 + Math.min(1, p.cover*2.5)*5 : 3;
    const cx = x(p.date).toFixed(1), cy = y(p.I).toFixed(1);
    const sel = p.id === selected;
    g += `<g class="pt${sel?" sel":""}" data-id="${esc(p.id)}" tabindex="0" role="button" aria-label="${esc(fmtDay(p.date))}: index ${p.I.toFixed(1)}, ${p.matched.length} repeat products">
      <circle cx="${cx}" cy="${cy}" r="14" fill="transparent"/>
      <circle class="ring" cx="${cx}" cy="${cy}" r="${(r+2).toFixed(1)}" fill="none" stroke="${sel?"var(--fg)":"transparent"}"/>
      <circle cx="${cx}" cy="${cy}" r="${r.toFixed(1)}" fill="${p.matched.length||i===0?"var(--accent)":"var(--surface)"}" stroke="var(--accent)" stroke-width="1.5"/></g>`;
  });
  const lp = pts[pts.length-1];
  g += `<text x="${Math.min(W-R, x(lp.date)+10).toFixed(1)}" y="${(y(lp.I)-10).toFixed(1)}" text-anchor="${x(lp.date) > W-80 ? "end" : "start"}" style="fill:var(--accent);font-weight:500">${lp.I.toFixed(1)}</text>`;
  return `<svg class="chart" viewBox="0 0 ${W} ${H}" role="img" aria-label="Your price index over time against official rates">${g}</svg>`;
}
function niceStep(raw){ const p = Math.pow(10, Math.floor(Math.log10(raw))); const f = raw/p; return (f<=1?1:f<=2?2:f<=2.5?2.5:f<=5?5:10)*p; }
function fmtNum(v, step){ return step < 1 ? v.toFixed(1) : String(Math.round(v)); }

function renderDetail(p){
  const el = $("detail");
  if (!p){ el.hidden = true; return; }
  el.hidden = false;
  const isFirst = p.id === sortedReceipts()[0]?.id;
  if (!p.matched.length){
    el.innerHTML = `<h3>${esc(fmtDay(p.date))} · ${esc(p.store||"Receipt")}</h3><p class="note">${p.food===0 ? "No food lines on this receipt." : ""} ${isFirst ? "Your first receipt sets the base: index 100." : "None of these products had been bought before, so the index stays where it was. They become comparison points for later receipts."} ${eur(p.food)} of food.</p>`;
    return;
  }
  el.innerHTML = `<div class="row" style="justify-content:space-between"><h3>${esc(fmtDay(p.date))} · ${esc(p.store||"Receipt")}</h3>
      <span class="status num">step ${pct(p.step*100)} · ${Math.round(p.cover*100)} % of ${eur(p.food)} matched ${p.cover<0.15?'<span class="chip thin">thin</span>':''}</span></div>
    <div class="tbl-wrap"><table><thead><tr><th>Product</th><th class="r">Before</th><th class="r">Now</th><th class="r">Change</th><th class="r">Weight</th></tr></thead><tbody>${
      p.matched.map(m=>`<tr><td>${esc(m.name)}${matchMode==="any"?`<div class="note">${esc(m.fromStore)} → ${esc(m.toStore)}</div>`:""}</td><td class="r num">${fmtUP(m.from,m.unit)}<div class="note">${esc(fmtDay(m.fromDate))}</div></td><td class="r num">${fmtUP(m.to,m.unit)}</td>
        <td class="r num ${cls((m.rel-1)*100)}">${pct((m.rel-1)*100)}</td><td class="r num">${Math.round(m.w/p.W*100)} %</td></tr>`).join("")
    }</tbody></table></div>`;
}

function renderMonths(pts){
  const box = $("monthBox"); box.hidden = false;
  const byM = {};
  for (const p of pts){ (byM[p.date.slice(0,7)] ||= []).push(p); }
  const months = Object.keys(byM).sort();
  let prevI = 100;
  const rows = months.map(m => {
    const ps = byM[m], endI = ps[ps.length-1].I;
    const mm = (endI/prevI - 1)*100; prevI = endI;
    const o = officialFor(m);
    const mix = basketFrom(ps.map(p=>p.r), effective(o));
    const nMatched = ps.reduce((a,p)=>a+p.matched.length,0);
    return `<tr><td>${fmtMonth(m)}</td><td class="r num">${ps.length}</td><td class="r num">${eur(ps.reduce((a,p)=>a+p.food,0))}</td>
      <td class="r num">${nMatched}</td><td class="r num">${endI.toFixed(1)}</td><td class="r num ${cls(mm)}">${m===months[0] && ps.length===1 ? "base" : pct(mm)}</td>
      <td class="r num">${pct(mix.de)}</td><td class="r num">${pct(o.de.food)}${o.month!==m?`<div class="note">${esc(fmtMonth(o.month))}</div>`:""}</td></tr>`;
  }).join("");
  box.innerHTML = `<table><thead><tr><th>Month</th><th class="r">Receipts</th><th class="r">Food spent</th><th class="r">Repeats</th><th class="r">Index</th><th class="r">Change</th><th class="r">Your mix, DE</th><th class="r">DE food</th></tr></thead><tbody>${rows}</tbody></table>
  <p class="note" style="margin-top:8px">Change is the month's move in your own index. “Your mix, DE” applies that month's official class rates to what you bought that month; “DE food” is the official annual rate. Where a month's figures aren't published yet, the latest available release stands in (shown in small type).</p>`;
}
