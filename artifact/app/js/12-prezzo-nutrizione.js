"use strict";
// ---- Prices × nutrition ----
// Nutrient-density score in the style of NRF9.3 (Drewnowski), per 100 kcal: eight nutrients to encourage
// (each capped at 100 % of the daily reference) minus three to limit. Vitamin E isn't tracked, so it is left out.
const NRF_ENC = [["p",50],["fib",30],["va",800,1],["vc",80,1],["ca",800,1],["fe",14,1],["mg",375,1],["k",2000,1],["n3",1.4],["unsat",44]];
const NRF_LIM = [["sf",20],["s",90],["salt",6]];
function nrfOf(pr, basis){
  if (!(pr.kcal > 0)) return null;
  // Per 100 kcal (default, as in NRF9.3) or per 100 g of edible food.
  const per = basis === "g" ? (v) => pr.kg > 0 ? v/(pr.kg*10) : 0 : (v) => v/pr.kcal*100;
  let enc = 0, lim = 0;
  for (const [k,ref,m] of NRF_ENC) enc += Math.min(100, per(m ? (pr.mic[k]||0) : k==="unsat" ? (pr.mufa||0)+(pr.pufa||0) : pr[k]) / ref * 100);
  if (pr.grainK > 0) enc += 50 * (pr.wgK||0)/pr.grainK;   // wholegrain: up to 50 points for grain products
  for (const [k,ref] of NRF_LIM) lim += per(pr[k]) / ref * 100;
  return enc - lim;
}
// How filling a food is, 0–100: mostly its weight per calorie (low energy density fills you up),
// then protein and fibre per calorie — the three strongest predictors of satiety in feeding studies.
function fillOf(pr){
  if (!(pr.kcal > 0)) return null;
  const g100 = pr.kg*1000/pr.kcal*100, p100 = pr.p/pr.kcal*100, f100 = pr.fib/pr.kcal*100;
  return 100*(0.5*Math.min(1, g100/250) + 0.3*Math.min(1, p100/8) + 0.2*Math.min(1, f100/4));
}
let scatY = "nrf", scatX = "kcal", scatCat = "all", scatCol = "ns";
function renderPriceNutrition(byProd){
  const card = $("nutPrice");
  const isG = scatX === "kg";
  const catsHere = [...new Set(Object.values(byProd).filter(p => p.kcal > 20 && p.spend > 0).map(p => p.cat))];
  if (scatCat !== "all" && !catsHere.includes(scatCat)) scatCat = "all";
  const prods = Object.values(byProd).filter(p => p.kcal > 20 && p.spend > 0 && p.kg > 0 && (scatCat === "all" || p.cat === scatCat)).map(p => {
    const nrf = nrfOf(p), nrfG = nrfOf(p, "g"), fill = fillOf(p), cpk = p.spend/p.kcal*1000, ckg = p.spend/p.kg;
    return {...p, nrf, nrfG, fill, cpk, ckg, xv: isG ? ckg : cpk, yv: scatY==="fill" ? fill : (isG ? nrfG : nrf)}; });
  const isF = scatY === "fill";
  const xUnit = isG ? "per kg" : "per 1,000 kcal";
  const catSel = `<label class="chk" for="scatCat">Show <select id="scatCat"><option value="all">all products</option>${CATS.filter(c=>catsHere.includes(c.k)).map(c=>`<option value="${c.k}"${scatCat===c.k?" selected":""}>${esc(c.n)}</option>`).join("")}</select></label>`;
  if (prods.length < 3){ card.innerHTML = `<h3>Prices and nutrition together</h3><div class="row" style="margin:8px 0">${catSel}</div><p class="empty">Fewer than three products in this group. Choose another one.</p>`; $("scatCat").addEventListener("change", e => { scatCat = e.target.value; scatPinned = null; renderPriceNutrition(byProd); }); return; }

  // --- scatter: price per 1,000 kcal (log) vs nutrient density
  const W = 640, H = 340, L = 44, Rr = 14, T = 16, B = 34;
  const xs = prods.map(p=>p.xv), ys = prods.map(p=>p.yv);
  const xlo = Math.max(0.3, Math.min(...xs)*0.8), xhi = Math.max(...xs)*1.25;
  const ylo = isF ? 0 : Math.min(isG ? -20 : -50, Math.min(...ys)), yhi = isF ? 100 : Math.max(isG ? 50 : 100, Math.max(...ys));
  const yr = (yhi-ylo)*0.06, y0 = ylo-yr, y1 = yhi+yr;
  const X = v => L + (Math.log(v)-Math.log(xlo))/(Math.log(xhi)-Math.log(xlo))*(W-L-Rr);
  const Y = v => T + (y1-v)/(y1-y0)*(H-T-B);
  const wmed = (arr, key) => { const a = [...arr].sort((m,n)=>m[key]-n[key]); const tot = a.reduce((s,p)=>s+p.spend,0); let acc = 0; for (const p of a){ acc += p.spend; if (acc >= tot/2) return p[key]; } return a[a.length-1][key]; };
  const mx = wmed(prods,"xv"), my = wmed(prods,"yv");
  // Spend-weighted trend: nutrient score against log price. Distance from it = more or fewer nutrients than usual for the price.
  let sw = 0, sx = 0, sy = 0; for (const p of prods){ const w = p.spend, lx = Math.log(p.xv); sw += w; sx += w*lx; sy += w*p.yv; }
  const mlx = sx/sw, mny = sy/sw; let sxx = 0, sxy = 0, syy = 0;
  for (const p of prods){ const w = p.spend, dx = Math.log(p.xv)-mlx, dy = p.yv-mny; sxx += w*dx*dx; sxy += w*dx*dy; syy += w*dy*dy; }
  const slope = sxx ? sxy/sxx : 0, icpt = mny - slope*mlx, r2 = sxx && syy ? (sxy*sxy)/(sxx*syy) : 0;
  const trend = v => icpt + slope*Math.log(v);
  prods.forEach(p => p.res = p.yv - trend(p.xv));
  const resSd = Math.sqrt(prods.reduce((a,p)=>a+p.spend*p.res*p.res,0)/sw) || 1;
  let g = "";
  for (const t of [0.5,1,2,5,10,20,50,100]) if (t >= xlo && t <= xhi){ const x = X(t).toFixed(1); g += `<line x1="${x}" x2="${x}" y1="${T}" y2="${H-B}" stroke="var(--grid)"/><text x="${x}" y="${H-B+14}" text-anchor="middle">${t<1?t.toFixed(1).replace(".",","):t} €</text>`; }
  const ystep = niceStep((y1-y0)/5);
  for (let v = Math.ceil(y0/ystep)*ystep; v <= y1; v += ystep){ const y = Y(v).toFixed(1); g += `<line x1="${L}" x2="${W-Rr}" y1="${y}" y2="${y}" stroke="var(--grid)"/><text x="${L-6}" y="${(+y+3).toFixed(1)}" text-anchor="end">${Math.round(v)}</text>`; }
  g += `<line x1="${X(mx).toFixed(1)}" x2="${X(mx).toFixed(1)}" y1="${T}" y2="${H-B}" stroke="var(--muted)" stroke-dasharray="4 3"/><line x1="${L}" x2="${W-Rr}" y1="${Y(my).toFixed(1)}" y2="${Y(my).toFixed(1)}" stroke="var(--muted)" stroke-dasharray="4 3"/>`;
  { const xa = xlo, xb = xhi, ya = Math.max(y0, Math.min(y1, trend(xa))), yb = Math.max(y0, Math.min(y1, trend(xb)));
    g += `<line x1="${X(xa).toFixed(1)}" y1="${Y(ya).toFixed(1)}" x2="${X(xb).toFixed(1)}" y2="${Y(yb).toFixed(1)}" stroke="var(--accent)" stroke-width="2" stroke-opacity=".75"/>`;
    g += `<text x="${(X(xb)-4).toFixed(1)}" y="${(Y(yb)-6).toFixed(1)}" text-anchor="end" style="fill:var(--accent);font-weight:600">trend</text>`; }
  const qa = isF ? ["Filling, cheap","Filling, pricey","Cheap, not filling","Pricey, not filling"] : ["Nutrient-rich, cheap","Nutrient-rich, pricey","Cheap energy","Pricey, few nutrients"];
  g += `<text class="q" x="${L+6}" y="${T+12}">${qa[0]}</text><text class="q" x="${W-Rr-6}" y="${T+12}" text-anchor="end">${qa[1]}</text>`;
  g += `<text class="q" x="${L+6}" y="${H-B-8}">${qa[2]}</text><text class="q" x="${W-Rr-6}" y="${H-B-8}" text-anchor="end">${qa[3]}</text>`;
  g += `<text x="${(L+W-Rr)/2}" y="${H-4}" text-anchor="middle">price ${xUnit} (log scale) →</text>`;
  const maxSp = Math.max(...prods.map(p=>p.spend));
  const nsCol = {A:"var(--nsA)",B:"var(--nsB)",C:"var(--nsC)",D:"var(--nsD)",E:"var(--nsE)"};
  const sorted = [...prods].sort((a,b)=>b.spend-a.spend);
  const order = [...sorted].reverse();
  order.forEach((p, i) => {
    const r = 3 + 9*Math.sqrt(p.spend/maxSp);
    g += `<circle class="dot" data-i="${i}" tabindex="0" role="button" aria-label="${esc(p.name)}" cx="${X(p.xv).toFixed(1)}" cy="${Y(p.yv).toFixed(1)}" r="${Math.max(r,4.5).toFixed(1)}" fill="${(scatCol === "co2" ? nsCol[co2Bin(p)] : nsCol[p.ns])||"var(--muted)"}" fill-opacity=".8" stroke="var(--surface)" stroke-width="1"></circle>`;
  });
  const placed = [];
  for (const p of sorted.slice(0, 14)){
    const x = X(p.xv), r = 3 + 9*Math.sqrt(p.spend/maxSp), label = p.name.length>22 ? p.name.slice(0,21)+"…" : p.name, tw = label.length*5.4;
    const right = x < W*0.7, tx = right ? x + r + 3 : x - r - 3, x0 = right ? tx : tx - tw;
    let y = Y(p.yv), ok = false;
    for (const dy of [0,-12,12,-24,24]){ const yy = y+dy; if (!placed.some(q => x0 < q[0]+q[2]+4 && q[0] < x0+tw+4 && Math.abs(q[1]-yy) < 11)){ y = yy; ok = true; break; } }
    if (!ok || placed.length >= 9) continue;
    placed.push([x0,y,tw]);
    g += `<text class="lb" x="${tx.toFixed(1)}" y="${(y+3.5).toFixed(1)}" text-anchor="${right?"start":"end"}">${esc(label)}</text>`;
  }
  // --- cheapest sources per nutrient
  const DAILY = [["p","Protein",50],["fib","Fibre",30],["vc","Vitamin C",80,1],["va","Vitamin A",800,1],["vd","Vitamin D",5,1],["b12","Vitamin B12",2.5,1],["fol","Folate",200,1],["ca","Calcium",800,1],["fe","Iron",14,1],["mg","Magnesium",375,1],["k","Potassium",2000,1],["zn","Zinc",10,1]];
  const cheap = DAILY.map(([k,n,ref,m]) => {
    const rows = prods.map(p => { const amt = m ? (p.mic[k]||0) : p[k]; const daysRef = amt/ref; return {p, daysRef, cpd: daysRef > 0.25 ? p.spend/daysRef : Infinity}; })
      .filter(r => isFinite(r.cpd)).sort((a,b)=>a.cpd-b.cpd).slice(0,3);
    return `<div><b>${esc(n)}</b><ol>${rows.map(r=>`<li>${esc(r.p.name)} <span>${eur(r.cpd)}</span></li>`).join("") || "<li>no source yet</li>"}</ol></div>`;
  }).join("");
  // --- possible savings: same comparable product, cheapest price seen anywhere
  const groups = {};
  for (const r of cleanReceipts()){
    for (const it of r.items){
      if (!isFood(it) || !it.g || !(it.price > 0)) continue;
      const cp = compPrice(it); if (cp.u === "pack") continue;
      const gk = it.g.toLowerCase().trim() + (it.bio ? "|bio" : "|conv") + "|" + cp.u;
      (groups[gk] ||= {name:it.g, bio:!!it.bio, u:cp.u, buys:[]}).buys.push({p:cp.p, units: it.price/cp.p, spend: it.price, store: chainLabel(r.store), date: r.date});
    }
  }
  const sav = Object.values(groups).map(gr => {
    const best = gr.buys.reduce((a,b)=> b.p < a.p ? b : a);
    const s = gr.buys.reduce((a,b)=> a + Math.max(0, (b.p - best.p)*b.units), 0);
    const spend = gr.buys.reduce((a,b)=>a+b.spend,0);
    return {...gr, best, s, spend, stores: new Set(gr.buys.map(b=>b.store))};
  }).filter(x => x.s > 0.05).sort((a,b)=>b.s-a.s);
  const savTot = sav.reduce((a,x)=>a+x.s,0), savBase = sav.reduce((a,x)=>a+x.spend,0);
  lastSav = {tot: savTot, base: savBase};
  scatOrder = order;
  card.innerHTML = `<h3>Prices and nutrition together</h3>
    <div class="row" style="margin:6px 0;gap:8px 16px">
      <div class="chips" id="scatXSel" role="group" aria-label="Price basis"><button type="button" id="sx-kcal" data-sx="kcal" aria-pressed="${!isG}">Price per 1,000 kcal</button><button type="button" id="sx-kg" data-sx="kg" aria-pressed="${isG}">Price per kg</button></div>
      <div class="chips" id="scatYSel" role="group" aria-label="Vertical axis"><button type="button" id="sy-nrf" data-sy="nrf" aria-pressed="${!isF}">Nutrient score</button><button type="button" id="sy-fill" data-sy="fill" aria-pressed="${isF}">How filling</button></div>
      <div class="chips" id="scatColSel" role="group" aria-label="Colour"><button type="button" data-sc="ns" aria-pressed="${scatCol==="ns"}">Colour: Nutri-Score</button><button type="button" data-sc="co2" aria-pressed="${scatCol==="co2"}">Colour: climate</button></div>
      ${catSel}</div>
    ${scatCol === "co2" ? `<div class="legend" style="margin:2px 0 4px">${CO2_BINS.map(b=>`<span><i class="sw" style="background:var(--ns${b[1]})"></i>${b[2]}</span>`).join("")}<span>kg CO₂e per 1,000 kcal</span></div>` : ""}
    <p class="note" style="margin:4px 0 8px">${isG
      ? `Each dot is a product you bought: further left is cheaper per kg of edible food, higher up ${isF ? "fills you up more per calorie" : "packs more nutrients per 100 g"}. Per kg is best for comparing within one group (pick it under “Show”): across groups a kilo of cucumber and a kilo of oats aren't interchangeable.`
      : isF ? "Each dot is a product you bought: further left is cheaper energy, higher up fills you up more per calorie (more weight per calorie, more protein and fibre)."
      : "Each dot is a product you bought: further left is cheaper energy, higher up packs more per calorie of protein, fibre, vitamins, minerals, omega-3 and unsaturated fat, plus wholegrain for grain products, against saturated fat, sugar and salt."} Dot size is what you spent, colour ${scatCol === "co2" ? "the climate footprint per 1,000 kcal, green lowest" : "the Nutri-Score"}. Dashed lines are the middle of your own spending.</p>
    <div class="scat-box" id="scatBox"><svg class="scat" id="scatSvg" viewBox="0 0 ${W} ${H}" role="img" aria-label="Products by price ${xUnit} and ${isF?"how filling they are":"nutrient density"}">${g}</svg><div class="tip" id="scatTip" hidden></div></div>
    <p class="status" style="margin-top:4px">Hover or tap a dot to see the product.</p>
    ${(() => { const pool = prods.filter(p => p.spend >= 1.5);
      const up = [...pool].sort((a,b)=>b.res-a.res).slice(0,6), dn = [...pool].sort((a,b)=>a.res-b.res).slice(0,6);
      const li = arr => arr.map(p=>`<li>${p.ns?`<span class="ns ${p.ns}" style="margin:0 5px 0 0">${p.ns}</span>`:""}${esc(p.name)}${p.bio?" ·bio":""} · <span>${p.res>=0?"+":"−"}${Math.round(Math.abs(p.res))}</span> <span class="status">· ${eur(p.xv)} ${xUnit}</span></li>`).join("");
      return `<div class="cheap" style="margin-top:12px"><div><b>${isF?"Most filling for the price":"Most nutrients for the price"}</b><ol>${li(up)}</ol></div><div><b>${isF?"Least filling for the price":"Fewest nutrients for the price"}</b><ol>${li(dn)}</ol></div></div>
      <p class="note" style="margin-top:6px">The red line is the trend across your basket, weighted by spending: the ${isF?"filling score":"nutrient score"} usually seen at each price. Numbers are points above or below it; products you spent under €1.50 on are left out of the lists. Price explains ${Math.round(r2*100)} % of the differences${isG
        ? (r2 < 0.15 ? `: per kg, price says little about ${isF?"how filling":"how nutritious"} a food is. The strong pattern in the per-1,000-kcal view comes mostly from dividing both price and nutrients by calories` : `, and the line ${slope>0?"rises":"falls"}: in this group, products that cost more per kg tend to be ${slope>0?"more":"less"} ${isF?"filling":"nutritious"}`)
        : slope > 0 ? `, and the line rises: in your basket, energy that costs more tends to ${isF?"fill you up more":"come with more nutrients"} (vegetables and fruit are cheap per kg but dear per calorie)` : ""}. Being far from the line is what matters, not which side of the median a product falls.</p>`; })()}
    <h3 style="margin-top:16px">Cheapest sources in your basket</h3>
    <p class="note" style="margin:4px 0 8px">What one day's reference intake of each nutrient cost you, product by product, at the prices you paid. Only products that supplied at least a quarter of a day's worth are listed.</p>
    <div class="cheap">${cheap}</div>
    <h3 style="margin-top:16px">Same product, best price you've paid</h3>
    ${sav.length ? `<p class="note" style="margin:4px 0 8px">Had every purchase of these products been at the lowest price per kg, litre or piece you've paid anywhere, you'd have spent <b>${eur(savTot)}</b> less on them (${Math.round(savTot/savBase*100)} % of ${eur(savBase)}). Organic and conventional are kept apart; the difference can come from the shop or from an offer.</p>
      <div class="tbl-wrap"><table><thead><tr><th>Product</th><th class="r">Best price</th><th>Where, when</th><th class="r">Extra paid</th></tr></thead><tbody>${sav.slice(0,8).map(x=>`<tr><td>${esc(x.name)}${x.bio?" ·bio":""}</td><td class="r num">${fmtUP(x.best.p,x.u)}</td><td>${esc(x.best.store)}, ${esc(fmtDay(x.best.date))}</td><td class="r num">${eur(x.s)}</td></tr>`).join("")}</tbody></table></div>`
      : `<p class="empty">No product has been bought at different prices per unit yet.</p>`}`;
  wireScatter();
  $("scatXSel").addEventListener("click", e => { const b = e.target.closest("button[data-sx]"); if (!b) return; scatX = b.dataset.sx; scatPinned = null; renderPriceNutrition(byProd); });
  $("scatCat").addEventListener("change", e => { scatCat = e.target.value; scatPinned = null; renderPriceNutrition(byProd); });
  $("scatColSel").addEventListener("click", e => { const b = e.target.closest("button[data-sc]"); if (!b) return; scatCol = b.dataset.sc; renderPriceNutrition(byProd); });
  $("scatYSel").addEventListener("click", e => { const b = e.target.closest("button[data-sy]"); if (!b) return; scatY = b.dataset.sy; scatPinned = null; renderPriceNutrition(byProd); });
}
