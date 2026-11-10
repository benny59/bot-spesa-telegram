"use strict";
function nsOf(it){ if (/^[A-E]$/.test(it.ns||"")) return {grade:it.ns, printed:true}; return nutriScore(it.nut, it.nsType, it.fvl); }
function nsBadge(g){ return g ? `<span class="ns ${g}" title="Nutri-Score ${g}">${g}</span>` : ""; }
// Net weight of one unit as bought (kg): weighed lines are per kg; else an explicit weight; else the printed size.
function weightPerUnit(it){
  if (it.unit === "kg") return {w:1, src:"weighed"};
  if (it.w > 0) return {w:it.w, src: it.wSrc === "label" ? "label" : "est"};
  const sz = parseSize(it.size);
  if (sz && sz.u !== "pc") return {w: sz.q*(sz.u==="l"?1.03:1), src:"label"};
  return null;
}
function per100(n, it){ return n.co2 ? co2Per100(it) : n.calc ? n.calc(it) : n.x ? (Number(it[n.x]?.[n.k])||0) : (Number(it.nut[n.k])||0); }
function lineNutrition(it){
  if (!isFood(it) || !it.nut) return null;
  const wu = weightPerUnit(it); if (!wu) return null;
  const kg = (it.qty||1) * wu.w * (it.ep > 0 && it.ep <= 1 ? it.ep : 1);
  const out = {kg, src:wu.src};
  for (const n of NUT) out[n.k] = kg*10*per100(n, it);
  out.mic = it.mic ? Object.fromEntries(MIC.map(m=>[m.k, kg*10*(Number(it.mic[m.k])||0)])) : null;
  return out;
}
let library = {};      // itemKey -> saved product label
let labShowAll = false, labTarget = null, labFiles = [], labCtl = null, labExtra = {ns:"", mic:{}};
function hashKey(s){ let h = 2166136261; for (const ch of s){ h ^= ch.codePointAt(0); h = Math.imul(h, 16777619); } return (h>>>0).toString(36); }
function prodDocId(key){ return "prod-" + hashKey(key); }
// Product memory, one document per product (store chain + article number). In order of strength:
// your corrections (rule: generic name, class, size, organic, climate type), typical values worked out
// again for a corrected product (est), and the label you photographed (nut, Nutri-Score, printed vitamins, weight).
function withLib(r, it){
  if (it._m) return it;
  let lib = library[itemKey(r.store, it)];
  if (!lib) return it;
  if (!lib.nut && eanDi(lib)){ const f = fratelloEan(lib); if (f) lib = {...lib, nut: f.nut, ns: f.ns, micPrinted: f.micPrinted, w: lib.w > 0 ? lib.w : f.w}; }   // stesso codice su un altro negozio: etichetta condivisa
  const m = {...it, _m: 1};
  const ru = lib.rule;
  if (ru){
    if (typeof ru.g === "string" && ru.g) m.g = ru.g;
    if (ru.cat && (CAT[ru.cat] || ru.cat === EXCLUDED)) m.cat = ru.cat;
    if (typeof ru.bio === "boolean") m.bio = ru.bio;
    if (typeof ru.size === "string" && it.unit !== "kg" && ru.size !== (it.size||"")){ m.size = ru.size; const sz = parseSize(ru.size); if (sz && sz.u !== "pc"){ delete m.w; delete m.wSrc; } }
    if (ru.ct && CO2T[ru.ct]) m.ct = ru.ct;
    m._rule = 1;
  }
  const es = lib.est;
  if (es && es.nut && !isLabelled(it)){
    m.nut = es.nut; m.nutSrc = "typical";
    for (const k of ["mic","fat2","nsType","fvl","ep"]) if (es[k] != null) m[k] = es[k];
    if (es.wg != null) m.wg = es.wg; else delete m.wg;
    if (es.ct && CO2T[es.ct] && !(ru && ru.ct)) m.ct = es.ct;
    const sz = parseSize(m.size);
    if (it.unit !== "kg" && es.w > 0 && !(sz && sz.u !== "pc") && m.wSrc !== "label"){ m.w = es.w; m.wSrc = "est"; }
    m._est = 1;
  }
  if (!lib.nut) return m;
  m.nut = lib.nut; m.nutSrc = "photo";
  if (lib.ns) m.ns = lib.ns;
  if (lib.micPrinted && Object.keys(lib.micPrinted).length) m.mic = {...(m.mic||{}), ...lib.micPrinted};
  if (it.unit !== "kg" && lib.w > 0){ m.w = lib.w; m.wSrc = "label"; }
  return m;
}
function isLabelled(it){ return !!it.nutSrc && it.nutSrc !== "typical"; }
function fmtInt(x){ return Math.round(x).toLocaleString("de-DE"); }
function fmtG(x){ return x >= 1000 ? (x/1000).toLocaleString("de-DE",{maximumFractionDigits:1})+" kg" : fmtInt(x)+" g"; }
function nutReceipts(){
  const list = cleanReceipts();
  if (nutPeriod === "all" || !list.length) return list;
  const last = list.reduce((a,r)=>a>r.date?a:r.date, "");
  return list.filter(r => days(r.date, last) < 30);
}
function renderNutrition(){
  const list = nutReceipts();
  let food = 0, counted = 0, labelled = 0; const bySrc = {weighed:0, label:0, est:0};
  const tot = Object.fromEntries(NUT.map(n=>[n.k,0]));
  const byCat = {}, byProd = {}, missing = [];
  const nsSpend = {A:0,B:0,C:0,D:0,E:0}, nsKcal = {A:0,B:0,C:0,D:0,E:0}; let nsPts = 0, nsW = 0;
  const micTot = Object.fromEntries(MIC.map(m=>[m.k,0])); let micKcal = 0, micSpend = 0;
  for (const r of list) for (const it0 of r.items){
    const it = withLib(r, it0);
    if (!isFood(it)) continue;
    food += it.price;
    const c = (byCat[it.cat] ||= {spend:0, kcal:0, p:0, fib:0});
    c.spend += it.price;
    const ln = lineNutrition(it);
    if (!ln){ missing.push({r, it}); continue; }
    counted += it.price; bySrc[ln.src] += it.price; if (isLabelled(it)) labelled += it.price;
    for (const n of NUT) tot[n.k] += ln[n.k];
    c.kcal += ln.kcal; c.p += ln.p; c.fib += ln.fib;
    const ns = nsOf(it);
    if (ns){ nsSpend[ns.grade] += it.price; nsKcal[ns.grade] += ln.kcal; }
    if (ln.mic){ for (const m of MIC) micTot[m.k] += ln.mic[m.k]; micKcal += ln.kcal; micSpend += it.price; }
    const pk = (it.g || it.name).toLowerCase() + (it.bio ? "|bio" : "");
    const pr = (byProd[pk] ||= {name: it.g || it.name, bio:!!it.bio, spend:0, kg:0, est:false, lab:false, cat:it.cat, ns: ns?.grade || "", mic:{}, ...Object.fromEntries(NUT.map(n=>[n.k,0]))});
    pr.n = (pr.n||0) + 1; (pr.stores ||= new Set()).add(chainLabel(r.store));
    pr.spend += it.price; pr.kg += ln.kg; if (ln.src === "est") pr.est = true; if (isLabelled(it)) pr.lab = true;
    for (const n of NUT) pr[n.k] += ln[n.k];
    if (ln.mic) for (const m of MIC) pr.mic[m.k] = (pr.mic[m.k]||0) + ln.mic[m.k];
  }
  $("nutPeriod").querySelectorAll("button").forEach(b => b.setAttribute("aria-pressed", b.dataset.np === nutPeriod));
  renderLabels();
  const fillBtn = $("nutFill");
  fillBtn.hidden = !(sample && db && uid && cleanReceipts().some(r => r.items.some(it => isFood(it) && (!it.nut || !it.mic || !it.fat2) && !/beleg|theke|bedien/i.test(it.name))));
  if (!counted){
    for (const id of ["nutShare","nutValue","nutDens","nutScore","nutMicro","nutRadar","nutPrice","nutFat","nutClimate","nutLong"]) $(id).hidden = true;
    $("nutTop").innerHTML = `<p class="empty">${list.length ? "None of these receipts has nutrition estimates yet. New receipts get them when they're read; for older ones use “Estimate missing lines” below." : "Save a receipt and its energy, protein and fibre per euro appear here."}</p>`;
    return;
  }
  for (const id of ["nutShare","nutValue","nutDens","nutScore","nutMicro","nutRadar","nutPrice","nutFat"]) $(id).hidden = false;
  const cov = counted/food;
  const missSpend = missing.reduce((a,m)=>a+m.it.price,0);
  const missTop = [...missing].sort((a,b)=>b.it.price-a.it.price).slice(0,3).map(m=>`${m.it.g||m.it.name} ${eur(m.it.price)}`);
  const dayEq = famDay("kcal") > 0 ? tot.kcal/famDay("kcal") : 0;
  $("nutTop").innerHTML = `<div class="ntiles">
      <div class="stat lead"><div class="k">Energy bought</div><div class="v num">${fmtInt(tot.kcal)}</div><div class="s">kcal · about ${dayEq < 10 ? dayEq.toLocaleString("de-DE",{maximumFractionDigits:1}) : fmtInt(dayEq)} days for your household</div></div>
      <div class="stat"><div class="k">Cost of energy</div><div class="v num">${eur(counted/tot.kcal*1000)}</div><div class="s">per 1,000 kcal · ${fmtInt(tot.kcal/counted)} kcal per €</div></div>
      <div class="stat"><div class="k">Protein</div><div class="v num">${(tot.p/counted).toLocaleString("de-DE",{maximumFractionDigits:1})} g</div><div class="s">per € · ${fmtG(tot.p)} in total</div></div>
      <div class="stat"><div class="k">Fibre</div><div class="v num">${(tot.fib/counted).toLocaleString("de-DE",{maximumFractionDigits:1})} g</div><div class="s">per € · ${fmtG(tot.fib)} in total</div></div>
    </div>
    <div style="margin-top:14px">
      <div class="status">Counted ${Math.round(cov*100)} % of ${eur(food)} food spending, ${fmtG(Object.values(byProd).reduce((a,p)=>a+p.kg,0)*1000)} of edible food. Nutrition from the product's own label for ${Math.round(labelled/counted*100)} % of that, typical values for the rest.</div>
      <div class="cover" role="img" aria-label="Weight source by spending">
        <span style="width:${(bySrc.weighed/food*100).toFixed(1)}%;background:var(--accent)"></span>
        <span style="width:${(bySrc.label/food*100).toFixed(1)}%;background:var(--accent);opacity:.6"></span>
        <span style="width:${(bySrc.est/food*100).toFixed(1)}%;background:var(--accent);opacity:.28"></span></div>
      <div class="legend"><span><i class="sw" style="background:var(--accent)"></i>weighed at the till ${Math.round(bySrc.weighed/food*100)} %</span>
        <span><i class="sw" style="background:var(--accent);opacity:.6"></i>pack size on receipt ${Math.round(bySrc.label/food*100)} %</span>
        <span><i class="sw" style="background:var(--accent);opacity:.28"></i>typical weight, est. ${Math.round(bySrc.est/food*100)} %</span>
        ${missSpend>0.005?`<span><i class="sw" style="background:var(--grid)"></i>not counted ${Math.round(missSpend/food*100)} % (${esc(missTop.join(", "))})</span>`:""}</div>
    </div>`;
  // Where the money goes vs what it buys, by class
  const cats = Object.entries(byCat).filter(([,c])=>c.spend>0).sort((a,b)=>b[1].spend-a[1].spend);
  const T = {spend:food, kcal:tot.kcal, p:tot.p};
  const maxShare = Math.max(...cats.flatMap(([,c])=>[c.spend/T.spend, c.kcal/T.kcal, c.p/T.p]));
  const sb = (v, col, op) => `<div class="sb"><span class="t"><i style="width:${(v/maxShare*100).toFixed(1)}%;background:${col};opacity:${op}"></i></span><span>${Math.round(v*100)} %</span></div>`;
  $("nutShare").innerHTML = `<div class="row" style="justify-content:space-between;margin-bottom:10px"><h3>Where the money goes, and what it buys</h3>
      <div class="legend" style="margin:0"><span><i class="sw" style="background:var(--fg);opacity:.7"></i>spending</span><span><i class="sw" style="background:var(--s2)"></i>energy</span><span><i class="sw" style="background:var(--s1)"></i>protein</span></div></div>
    <div class="share">${cats.map(([k,c]) => `<div class="share-row"><div class="nm">${esc(CAT[k].n)}</div><div class="share-bars">${sb(c.spend/T.spend,"var(--fg)",.7)}${sb(c.kcal/T.kcal,"var(--s2)",1)}${sb(c.p/T.p,"var(--s1)",1)}</div></div>`).join("")}</div>
    <p class="note" style="margin-top:10px">Shares of your food spending, of the energy it bought and of the protein. A class whose energy or protein bar is longer than its spending bar gives more of that per euro than your average purchase.${cov < 0.999 ? " Lines without a nutrition estimate count towards spending only." : ""}</p>`;
  // Value per euro by product
  const isNpe = nutMetric === "npe";
  const metric = isNpe ? {k:"npe", n:"Nutrients"} : (NUT.find(n=>n.k===nutMetric) || NUT[0]);
  // Nutrients per euro (Drewnowski): nutrient score per 100 kcal × how many 100 kcal one euro buys.
  const prods = Object.values(byProd).filter(p=>p.spend>0 && (isNpe ? p.kcal > 20 : p[metric.k]>0))
    .map(p=>({...p, v: isNpe ? (nrfOf(p)||0) * (p.kcal/100) / p.spend / 100 : p[metric.k]/p.spend})).filter(p=>p.v>0).sort((a,b)=>b.v-a.v);
  const vmax = Math.max(...prods.map(p=>p.v));
  const unitTxt = isNpe ? "pts/€" : metric.k==="kcal" ? "kcal/€" : "g/€";
  $("nutValue").innerHTML = `<div class="row" style="justify-content:space-between;margin-bottom:10px"><h3>${esc(metric.n)} per euro, by product</h3>
      <div class="chips" id="nutMetric" role="group" aria-label="Nutrient">${["npe","kcal","p","fib","n3"].map(k=>`<button type="button" id="nm-${k}" data-nm="${k}" aria-pressed="${k===nutMetric}">${k==="npe"?"All nutrients":esc(NUT.find(n=>n.k===k).n)}</button>`).join("")}</div></div>
    <div class="vlist">${prods.map(p => `<div class="vrow"><div class="nm" title="${esc(p.name)}">${p.ns?`<span class="ns ${p.ns}" style="margin:0 6px 0 0" title="Nutri-Score ${p.ns}">${p.ns}</span>`:""}${esc(p.name)}${p.bio?" ·bio":""}<small>${eur(p.spend/p.kg)}/kg${p.est?" est.":""} · ${eur(p.spend)} · ${p.lab?"label":"typical"}</small></div>
      <div><div class="bar" style="width:${(p.v/vmax*100).toFixed(1)}%"></div></div><div class="v">${p.v>=100?fmtInt(p.v):p.v.toLocaleString("de-DE",{maximumFractionDigits:1})} ${unitTxt}</div></div>`).join("")}</div>
    <p class="note" style="margin-top:8px">${isNpe ? "“All nutrients” is nutrients per euro (after Drewnowski): the nutrient score per 100 kcal times how many 100 kcal a euro buys, divided by 100. It rewards foods that are both nutrient-dense and cheap; products whose score is negative (more saturated fat, sugar and salt than nutrients) are left out. " : ""}${prods.length} products, best value first. The small line shows the price per kg of edible food, what you spent in total, and whether the nutrition comes from the product's label or is a typical value.</p>`;
  $("nutMetric").addEventListener("click", e => { const b = e.target.closest("button[data-nm]"); if (!b) return; nutMetric = b.dataset.nm; renderNutrition(); });
  // Density per 1,000 kcal against reference intakes + macro split
  const per = k => tot[k]/tot.kcal*1000;
  const eP = tot.p*4, eF = tot.f*9, eC = tot.c*4, eAll = eP+eF+eC+tot.fib*2;
  const top3 = k => Object.values(byProd).filter(p=>p[k]>0).sort((a,b)=>b[k]-a[k]).slice(0,3).map(p=>`${p.name} ${Math.round(p[k]/tot[k]*100)} %`).join(", ");
  $("nutDens").innerHTML = `<h3 style="margin-bottom:10px">Per 1,000 kcal of what you bought</h3>
    <div class="macro" role="img" aria-label="Energy from protein ${Math.round(eP/eAll*100)} percent, fat ${Math.round(eF/eAll*100)} percent, carbohydrate ${Math.round(eC/eAll*100)} percent">
      <span style="width:${(eP/eAll*100).toFixed(1)}%;background:var(--s1)"></span><span style="width:${(eF/eAll*100).toFixed(1)}%;background:var(--s2)"></span><span style="width:${(eC/eAll*100).toFixed(1)}%;background:var(--s3)"></span><span style="width:${(tot.fib*2/eAll*100).toFixed(1)}%;background:var(--s5)"></span></div>
    <div class="legend" style="margin-bottom:14px"><span><i class="sw" style="background:var(--s1)"></i>protein ${Math.round(eP/eAll*100)} % of energy</span><span><i class="sw" style="background:var(--s2)"></i>fat ${Math.round(eF/eAll*100)} %</span><span><i class="sw" style="background:var(--s3)"></i>carbohydrate ${Math.round(eC/eAll*100)} %</span><span><i class="sw" style="background:var(--s5)"></i>fibre ${Math.round(tot.fib*2/eAll*100)} %</span></div>
    <div class="dens">${NUT.filter(n=>n.ref).map(n => { const v = per(n.k), ref = famPer1000(n.k), mx = Math.max(v, ref)*1.15;
      return `<div class="drow"><div>${esc(n.n)}</div><div class="t"><i style="width:${(v/mx*100).toFixed(1)}%"></i><b style="left:${(ref/mx*100).toFixed(1)}%" title="Reference ${ref.toFixed(1)} g"></b></div>
        <div class="v">${v.toLocaleString("de-DE",{maximumFractionDigits:1})} g <span class="status">/ ${ref < 10 ? ref.toLocaleString("de-DE",{maximumFractionDigits:1}) : Math.round(ref)}</span></div><div class="src">from ${esc(top3(n.k))}</div></div>`; }).join("")}</div>
    <p class="note" style="margin-top:10px">The black mark is the reference amount per 1,000 kcal for your household (${esc(householdText())}), from EU adult reference intakes and German Nutrition Society values for children. Below each bar are the three products that supplied most of it.</p>`;
  renderRadar();
  renderPriceNutrition(byProd);
  renderFatGrain(tot, byProd);
  renderLongevity(tot, list);
  renderClimate(tot, byProd, list, counted, food);
  lastNut = {tot, byProd, nsSpend, counted, food};
  // Nutri-Score of the spending
  const G = ["A","B","C","D","E"], nsTot = G.reduce((a,g)=>a+nsSpend[g],0);
  const worst = Object.values(byProd).filter(p=>p.ns==="D"||p.ns==="E").sort((a,b)=>b.spend-a.spend).slice(0,5);
  const best = Object.values(byProd).filter(p=>p.ns==="A").sort((a,b)=>b.spend-a.spend).slice(0,5);
  $("nutScore").innerHTML = nsTot ? `<h3 style="margin-bottom:10px">Nutri-Score of what you buy</h3>
    <div class="nsbar" role="img" aria-label="${G.map(g=>`${g} ${Math.round(nsSpend[g]/nsTot*100)} percent`).join(", ")} of spending">${G.map(g=>`<span class="${g}" style="width:${(nsSpend[g]/nsTot*100).toFixed(1)}%">${nsSpend[g]/nsTot>0.06?g:""}</span>`).join("")}</div>
    <div class="nsgrid">${G.map(g=>`<div>${nsBadge(g)} <b class="num">${Math.round(nsSpend[g]/nsTot*100)} %</b>of spending · ${Math.round(nsKcal[g]/tot.kcal*100)} % of energy</div>`).join("")}</div>
    ${best.length?`<p class="note" style="margin-top:12px">Most spent on A: ${esc(best.map(p=>p.name).join(", "))}.</p>`:""}
    ${worst.length?`<p class="note" style="margin-top:4px">Most spent on D and E: ${esc(worst.map(p=>`${p.name} (${p.ns})`).join(", "))}.</p>`:""}` : "";
  // Vitamins and minerals
  if (!micKcal){ $("nutMicro").hidden = true; } else {
    $("nutMicro").innerHTML = `<h3 style="margin-bottom:4px">Vitamins and minerals</h3>
      <p class="note" style="margin-bottom:12px">How many days of your household's reference intake your groceries contain, and how much each 1,000 kcal supplies against the reference for 1,000 kcal (the black mark).${micSpend < counted*0.98 ? ` Based on ${Math.round(micSpend/counted*100)} % of counted spending.` : ""}</p>
      <div class="dens">${MIC.map(m => { const perK = micTot[m.k]/micKcal*1000, ref = famPer1000(m.k), mx = Math.max(perK, ref)*1.15, days = famDay(m.k) > 0 ? micTot[m.k]/famDay(m.k) : 0;
        const src = Object.values(byProd).filter(p=>p.mic[m.k]>0).sort((a,b)=>b.mic[m.k]-a.mic[m.k]).slice(0,3).map(p=>`${p.name} ${Math.round(p.mic[m.k]/micTot[m.k]*100)} %`).join(", ");
        return `<div class="drow"><div>${esc(m.n)}</div><div class="t"><i style="width:${(perK/mx*100).toFixed(1)}%;background:var(--s1)"></i><b style="left:${(ref/mx*100).toFixed(1)}%"></b></div>
          <div class="v">${Math.round(perK/ref*100)} % · ${days<10?days.toLocaleString("de-DE",{maximumFractionDigits:1}):fmtInt(days)} d</div><div class="src">from ${esc(src||"–")}</div></div>`; }).join("")}</div>
      <p class="note" style="margin-top:10px">“d” is days of your household's reference intake in everything you bought. Vitamin D mostly comes from sunlight rather than food, so a low figure here is normal.</p>`;
  }
}
