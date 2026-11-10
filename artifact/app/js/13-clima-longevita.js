"use strict";
// ---- Climate footprint of the shopping ----
const CO2_BINS = [[0.5,"A","under 0.5"],[1,"B","0.5–1"],[2,"C","1–2"],[4,"D","2–4"],[Infinity,"E","4 or more"]];
function co2Int(p){ return p.kcal > 0 ? p.co2/p.kcal : 0; }        // g per kcal = kg CO2e per 1,000 kcal
function co2Bin(p){ const v = co2Int(p); return CO2_BINS.find(b => v < b[0])[1]; }
function renderClimate(tot, byProd, list, counted, food){
  const card = $("nutClimate");
  if (!(tot.co2 > 0) || !(tot.kcal > 0)){ card.hidden = true; return; }
  card.hidden = false;
  const dates = list.map(r => r.date).sort(), wks = Math.max(1, (days(dates[0], dates[dates.length-1]) + 7)/7);
  const kcal1000 = tot.co2/tot.kcal;                 // kg per 1,000 kcal
  const perDay = kcal1000*2;                          // kg for a 2,000 kcal day
  const P = Object.values(byProd).filter(p => p.co2 > 0);
  // by climate group
  const grp = {};
  for (const r of list) for (const it of r.items){
    if (!isFood(it)) continue; const ln = lineNutrition(it); if (!ln) continue;
    const gname = CO2_GROUP_OF[co2Type(it)] || "Other";
    const G = (grp[gname] ||= {co2:0, spend:0, kcal:0, p:0}); G.co2 += ln.co2; G.spend += it.price; G.kcal += ln.kcal; G.p += ln.p;
  }
  const gl = Object.entries(grp).sort((a,b)=>b[1].co2-a[1].co2);
  const mxS = Math.max(...gl.flatMap(([,g]) => [g.co2/tot.co2, g.spend/counted, g.kcal/tot.kcal]));
  const sb = (v, col, op) => `<div class="sb"><span class="t"><i style="width:${(v/mxS*100).toFixed(1)}%;background:${col};opacity:${op}"></i></span><span>${Math.round(v*100)} %</span></div>`;
  const top = [...P].sort((a,b)=>b.co2-a.co2).slice(0, 8), topMx = top[0]?.co2 || 1;
  // protein sources: cost and climate per 10 g of protein
  const prot = P.filter(p => p.kg > 0 && p.p*4 >= 0.2*p.kcal && p.p/p.kg/10 >= 5 && p.p >= 30).map(p => ({...p, cpp: p.spend/p.p*10, gpp: p.co2/p.p*10})).sort((a,b)=>a.gpp-b.gpp);
  const mxG = Math.max(...prot.map(p=>p.gpp), 1), mxC = Math.max(...prot.map(p=>p.cpp), 0.01);
  // gauge: kg per 2,000 kcal day
  const gMax = Math.max(6, Math.ceil(perDay+0.5)), gx = v => Math.min(100, v/gMax*100);
  card.innerHTML = `<h3>Climate footprint of your food</h3>
    <div class="ntiles" style="margin-top:10px">
      <div class="stat lead"><div class="k">Footprint</div><div class="v num">${fmtKg(tot.co2)}</div><div class="s">CO₂e for the food bought · about ${fmtKg(tot.co2/wks)} a week</div></div>
      <div class="stat"><div class="k">Per 1,000 kcal</div><div class="v num">${kcal1000.toLocaleString("de-DE",{maximumFractionDigits:2})} kg</div><div class="s">${fmtInt(tot.co2/counted)} g CO₂e per euro spent</div></div>
      <div class="stat"><div class="k">As one person's day</div><div class="v num">${perDay.toLocaleString("de-DE",{minimumFractionDigits:1, maximumFractionDigits:1})} kg</div><div class="s">for 2,000 kcal of this mix</div></div>
    </div>
    <div class="gauge" role="img" aria-label="${perDay.toFixed(1)} kilograms CO2e per 2,000 kcal day, against ${CO2_GOOD_DAY} climate-friendlier and ${CO2_AVG_DAY} German average">
      <div class="gt"><i style="width:${gx(perDay).toFixed(1)}%;background:${perDay < CO2_GOOD_DAY ? "var(--nsB)" : perDay < CO2_AVG_DAY ? "var(--nsC)" : "var(--nsE)"}"></i><b style="left:${gx(CO2_GOOD_DAY).toFixed(1)}%"></b><b style="left:${gx(CO2_AVG_DAY).toFixed(1)}%"></b></div>
      <div class="gk gk1" style="left:${gx(CO2_GOOD_DAY).toFixed(1)}%">climate-friendlier ${CO2_GOOD_DAY.toLocaleString("de-DE")}</div><div class="gk gk2" style="left:${gx(CO2_AVG_DAY).toFixed(1)}%">German average ${CO2_AVG_DAY.toLocaleString("de-DE")}</div>
    </div>
    <p class="note" style="margin-top:4px">Food in Germany averages about 1.7 tonnes CO₂e per person a year, roughly ${CO2_AVG_DAY.toLocaleString("de-DE")} kg a day; a mostly plant-based mix with less meat, cheese and butter cuts that by up to 40 %. Your figure is for food as bought, so it includes anything thrown away; it leaves out cooking at home and eating out.</p>
    <h3 style="margin-top:16px">Where it comes from</h3>
    <div class="legend" style="margin:4px 0 8px"><span><i class="sw" style="background:var(--nsE)"></i>climate footprint</span><span><i class="sw" style="background:var(--fg);opacity:.7"></i>spending</span><span><i class="sw" style="background:var(--s2)"></i>energy</span></div>
    <div class="share">${gl.map(([n,g]) => `<div class="share-row"><div class="nm">${esc(n)}</div><div class="share-bars">${sb(g.co2/tot.co2,"var(--nsE)",.9)}${sb(g.spend/counted,"var(--fg)",.7)}${sb(g.kcal/tot.kcal,"var(--s2)",1)}</div></div>`).join("")}</div>
    <h3 style="margin-top:16px">Biggest single sources</h3>
    <div class="vlist" style="max-height:none;margin-top:6px">${top.map(p => `<div class="vrow"><div class="nm" title="${esc(p.name)}">${esc(p.name)}${p.bio?" ·bio":""}<small>${(p.co2/p.kg/1000).toLocaleString("de-DE",{maximumFractionDigits:1})} kg/kg · ${(co2Int(p)).toLocaleString("de-DE",{maximumFractionDigits:1})} per 1,000 kcal</small></div>
      <div><div class="bar" style="width:${(p.co2/topMx*100).toFixed(1)}%;background:var(--nsE)"></div></div><div class="v">${fmtKg(p.co2)} · ${Math.round(p.co2/tot.co2*100)} %</div></div>`).join("")}</div>
    ${prot.length >= 3 ? `<h3 style="margin-top:16px">Protein, priced in money and in climate</h3>
    <p class="note" style="margin:4px 0 8px">For each protein-rich product (at least a fifth of its energy from protein): what 10 g of protein from it cost you, and its footprint. The lowest footprint comes first.</p>
    <div class="prot">${prot.slice(0, 12).map(p => `<div class="pr"><div class="nm">${esc(p.name)}${p.bio?" ·bio":""}</div>
      <div class="b2"><span class="t"><i style="width:${(p.gpp/mxG*100).toFixed(1)}%;background:var(--nsE)"></i></span><span>${fmtInt(p.gpp)} g CO₂e</span></div>
      <div class="b2"><span class="t"><i style="width:${(p.cpp/mxC*100).toFixed(1)}%;background:var(--fg);opacity:.7"></i></span><span>${eur(p.cpp)}</span></div></div>`).join("")}</div>` : ""}
    <details style="margin-top:12px"><summary class="status" style="font-weight:500">How this is worked out</summary>
      <p class="note" style="margin-top:6px">Each product gets the footprint of its kind of food at the shop shelf in Germany: farming, processing, packaging, transport and the shop, per kg as bought, from the ifeu study for the German Environment Agency (2020). Products the study doesn't cover take the value of their nearest kind and are marked as estimates in Product memory. Organic and conventional, or one brand and another, aren't told apart, so this shows which foods drive your footprint rather than differences between brands. You can change a product's climate type in Product memory on the Receipts page.</p></details>`;
}
// ---- Longevity check: the shopping as one person's 2,000 kcal day ----
function renderLongevity(tot, list){
  const card = $("nutLong");
  if (!(tot.kcal > 0)){ card.hidden = true; return; }
  card.hidden = false;
  const items = [], f = 2000/tot.kcal; let plantP = 0, sweetsK = 0;
  for (const r of list) for (const it of r.items){ if (!isFood(it)) continue; const ln = lineNutrition(it); if (!ln) continue; items.push({...it, ct: co2Type(it), _kg: ln.kg}); if (isPlantCt(co2Type(it))) plantP += ln.p; if (it.cat === "sweets") sweetsK += ln.kcal; }
  const g = longGrams(items, it => it._kg);
  const rows = LONG.map(L => ({n: L.n, v: g[L.k]*f, t: L.min || L.max, lim: !!L.max, u: "g", src: L.src, wk: ["fish","meat","rpm"].includes(L.k)}));
  rows.push({n:"Plant share of protein", v: tot.p > 0 ? plantP/tot.p*100 : 0, t: 50, u:"%", src:"Song 2016: swapping animal for plant protein went with lower mortality; DGE 2024: three-quarters of food from plants"});
  rows.push({n:"Fibre", v: tot.fib*f, t: 30, u:"g", src:"DGE 30 g; Reynolds 2019: benefits rise to 25–29 g and beyond"});
  rows.push({n:"Salt", v: tot.salt*f, t: 5, u:"g", lim: true, src:"WHO: under 5 g a day"});
  rows.push({n:"Saturated fat", v: tot.sf*9/tot.kcal*100, t: 10, u:"% of energy", lim: true, src:"WHO: under 10 % of energy"});
  rows.push({n:"Sweets and sugar", v: sweetsK/tot.kcal*100, t: 5, u:"% of energy", lim: true, src:"WHO: free sugars ideally under 5 % of energy"});
  const ok = r => r.lim ? r.v <= r.t*1.05 : r.v >= r.t*0.9;
  const nOk = rows.filter(ok).length;
  const fmtV = (v, u) => u === "g" ? (v >= 100 ? fmtInt(v) : v.toLocaleString("de-DE",{maximumFractionDigits: v < 10 ? 1 : 0})) + " g" : Math.round(v) + (u === "%" ? " %" : " %");
  const sev = r => r.lim ? r.v/r.t : r.t/Math.max(r.v, 0.1);
  const gaps = rows.filter(r => !ok(r)).sort((a,b) => sev(b) - sev(a)).slice(0, 3).map(r => r.n.toLowerCase());
  card.innerHTML = `<div class="row" style="justify-content:space-between"><h3>Longevity check</h3><span class="status">${nOk} of ${rows.length} on target</span></div>
    <p class="note" style="margin:4px 0 10px">Everything you bought, scaled to one adult's 2,000 kcal day, against the food groups linked most strongly to a longer, healthier life.${gaps.length ? ` Biggest gaps: ${esc(gaps.join(", "))}.` : ""}</p>
    <div class="ptab">${rows.map(r => { const pv = r.v/r.t*100;
      return `<div class="pr" title="${esc(r.src)}"><span>${esc(r.n)}${r.lim?' <span class="status">max</span>':""}<small>${r.lim ? "under " : "target "}${fmtV(r.t, r.u)}${r.wk ? ` · ${fmtInt(r.t*7)} g a week` : ""}</small></span>${pctBar(pv, null, r.lim)}<span class="num ${ok(r) ? "" : "up"}">${fmtV(r.v, r.u)}</span></div>`; }).join("")}</div>
    <details style="margin-top:10px"><summary class="status" style="font-weight:500">Where the targets come from</summary>
      <ul class="note" style="margin:6px 0 0;padding-left:18px">${rows.map(r => `<li><b>${esc(r.n)}</b>: ${esc(r.src)}</li>`).join("")}</ul>
      <p class="note" style="margin-top:6px">In the life-expectancy model of Fadnes and colleagues (PLOS Medicine 2022), moving from a typical Western diet towards these groups added the most years through legumes, whole grains and nuts, and through less red and processed meat. The figures here are what was bought, including food the children ate and anything thrown away, so they show the direction of your shopping rather than what any one person ate.</p></details>`;
}
function renderFatGrain(tot, byProd){
  const P = Object.values(byProd);
  const unsat = (tot.mufa + tot.pufa), uShare = tot.f > 0 ? unsat/tot.f : 0, sShare = tot.f > 0 ? tot.sf/tot.f : 0;
  const n3days = famDay("n3") > 0 ? tot.n3/famDay("n3") : 0;
  const top = (k, n) => P.filter(p=>p[k]>0).sort((a,b)=>b[k]-a[k]).slice(0,n);
  const satSrc = top("sf",4).map(p=>`${p.name} ${Math.round(p.sf/tot.sf*100)} %`).join(", ");
  const unsSrc = P.filter(p=>(p.mufa+p.pufa)>0).sort((a,b)=>(b.mufa+b.pufa)-(a.mufa+a.pufa)).slice(0,4).map(p=>`${p.name} ${Math.round((p.mufa+p.pufa)/unsat*100)} %`).join(", ");
  const n3Src = top("n3",4).map(p=>`${p.name} ${Math.round(p.n3/tot.n3*100)} %`).join(", ");
  const grains = P.filter(p=>p.grainK>0).sort((a,b)=>b.spend-a.spend);
  const wgShare = tot.grainK > 0 ? tot.wgK/tot.grainK : 0;
  const refined = grains.filter(p=>p.wgK/p.grainK < 0.5).slice(0,5), whole = grains.filter(p=>p.wgK/p.grainK >= 0.5).slice(0,5);
  const fills = P.filter(p=>p.kcal>20).map(p=>({...p, fill:fillOf(p)}));
  const fW = fills.reduce((a,p)=>a+p.kcal,0), fAvg = fW ? fills.reduce((a,p)=>a+p.fill*p.kcal,0)/fW : 0;
  const bar = (v, col) => `<div class="cover" style="height:10px;margin:4px 0 2px"><span style="width:${(v*100).toFixed(1)}%;background:${col}"></span></div>`;
  $("nutFat").innerHTML = `<h3 style="margin-bottom:10px">Fat quality, omega-3, wholegrain and fullness</h3>
    <div class="ntiles">
      <div class="stat"><div class="k">Unsaturated fat</div><div class="v num">${Math.round(uShare*100)} %</div><div class="s">of the fat you bought · saturated ${Math.round(sShare*100)} %</div>${bar(uShare,"var(--down)")}</div>
      <div class="stat"><div class="k">Omega-3</div><div class="v num">${tot.n3.toLocaleString("de-DE",{maximumFractionDigits:0})} g</div><div class="s">about ${n3days<10?n3days.toLocaleString("de-DE",{maximumFractionDigits:1}):fmtInt(n3days)} days for your household</div></div>
      <div class="stat"><div class="k">Wholegrain</div><div class="v num">${Math.round(wgShare*100)} %</div><div class="s">of the energy from grain products</div>${bar(wgShare,"var(--s3)")}</div>
      <div class="stat"><div class="k">How filling</div><div class="v num">${Math.round(fAvg)}</div><div class="s">out of 100, average per calorie bought</div>${bar(fAvg/100,"var(--s1)")}</div>
    </div>
    <div class="dens" style="margin-top:14px">
      <div><b style="font-size:13px">Fats</b><p class="note">Most unsaturated fat from ${esc(unsSrc||"–")}. Most saturated fat from ${esc(satSrc||"–")}.</p></div>
      <div><b style="font-size:13px">Omega-3</b><p class="note">From ${esc(n3Src||"–")}. The household reference is about ${famDay("n3").toLocaleString("de-DE",{maximumFractionDigits:1})} g a day (EFSA: plant omega-3 at 0.5 % of energy plus 250 mg of the fish fats EPA and DHA for adults). Plant omega-3 from linseed and walnuts is only partly turned into EPA and DHA, so oily fish counts for more than its grams suggest.</p></div>
      <div><b style="font-size:13px">Grain products</b><p class="note">${whole.length?`Wholegrain: ${esc(whole.map(p=>p.name).join(", "))}. `:""}${refined.length?`Mostly refined: ${esc(refined.map(p=>p.name).join(", "))}.`:""} The German Nutrition Society recommends choosing wholegrain for most bread, pasta, rice and cereals.</p></div>
      <div><b style="font-size:13px">Fullness</b><p class="note">The score is mostly weight per calorie (watery, low energy-density foods fill the stomach), then protein and fibre per calorie. These three are the strongest predictors of fullness in feeding studies; fat, sugar and very dry foods fill least per calorie. Switch the price chart to “How filling” to compare products.</p></div>
    </div>`;
}
let scatOrder = [], scatPinned = null;
function wireScatter(){
  const box = $("scatBox"), svg = $("scatSvg"), tip = $("scatTip"); if (!box) return;
  const show = (el) => {
    const p = scatOrder[+el.dataset.i]; if (!p) return;
    svg.querySelectorAll("circle.dot.on").forEach(c => c.classList.remove("on")); el.classList.add("on");
    tip.innerHTML = `<b>${esc(p.name)}</b>${p.bio?" · organic":""}${p.ns?` <span class="ns ${p.ns}">${p.ns}</span>`:""}<br>
      ${eur(p.cpk)} <span class="k">per 1,000 kcal</span> · ${eur(p.spend/p.kg)}<span class="k">/kg</span><br>
      <span class="k">Nutrient score</span> ${Math.round(p.nrf)} <span class="k">per 100 kcal</span> · ${Math.round(p.nrfG)} <span class="k">per 100 g</span><br><span class="k">Filling</span> ${Math.round(p.fill)}/100 · ${fmtInt(p.kcal/p.kg/10)} <span class="k">kcal/100 g</span><br>
      ${p.f > 0.5 ? `${Math.round(((p.mufa||0)+(p.pufa||0))/p.f*100)} % <span class="k">of fat unsaturated</span> · ` : ""}${(p.n3/p.kg/10) >= 0.05 ? `${(p.n3/p.kg/10).toLocaleString("de-DE",{maximumFractionDigits:1})} g <span class="k">omega-3/100 g</span>` : `<span class="k">little omega-3</span>`}${p.grainK > 0 ? ` · ${Math.round(p.wgK/p.grainK*100)} % <span class="k">wholegrain</span>` : ""}<br>
      ${(p.p/p.kg/10).toLocaleString("de-DE",{maximumFractionDigits:1})} g <span class="k">protein</span> · ${(p.fib/p.kg/10).toLocaleString("de-DE",{maximumFractionDigits:1})} g <span class="k">fibre per 100 g</span><br>
      <span style="color:${p.res>=0?"var(--down)":"var(--up)"}">${p.res>=0?"Above":"Below"} the trend by ${Math.round(Math.abs(p.res))} points</span> <span class="k">(${scatX==="kg"?"per kg view":"per 1,000 kcal view"})</span><br>
      <span class="k">Climate</span> ${(p.co2/p.kg/1000).toLocaleString("de-DE",{maximumFractionDigits:1})} kg CO₂e/kg · ${co2Int(p).toLocaleString("de-DE",{maximumFractionDigits:1})} <span class="k">per 1,000 kcal</span><br>
      <span class="k">Spent</span> ${eur(p.spend)} · ${p.n||1}× · ${esc([...(p.stores||[])].join(", "))}<br><span class="k">${p.lab?"Nutrition from the label":"Typical nutrition values"}</span>`;
    tip.hidden = false;
    const bb = box.getBoundingClientRect(), cb = el.getBoundingClientRect();
    const cx = cb.left + cb.width/2 - bb.left, cy = cb.top - bb.top;
    const tw = tip.offsetWidth, th = tip.offsetHeight;
    let left = cx - tw/2; left = Math.max(0, Math.min(bb.width - tw, left));
    let top = cy - th - 8; if (top < 0) top = cb.bottom - bb.top + 8;
    tip.style.left = left + "px"; tip.style.top = top + "px";
  };
  const hide = () => { if (scatPinned) return; tip.hidden = true; svg.querySelectorAll("circle.dot.on").forEach(c => c.classList.remove("on")); };
  svg.addEventListener("pointerover", e => { if (e.target.classList?.contains("dot") && e.pointerType === "mouse" && !scatPinned) show(e.target); });
  svg.addEventListener("pointerout", e => { if (e.target.classList?.contains("dot") && e.pointerType === "mouse") hide(); });
  svg.addEventListener("click", e => {
    if (e.target.classList?.contains("dot")){ scatPinned = e.target.dataset.i; show(e.target); }
    else { scatPinned = null; hide(); }
  });
  svg.addEventListener("focusin", e => { if (e.target.classList?.contains("dot")) show(e.target); });
  svg.addEventListener("focusout", () => { scatPinned = null; hide(); });
  if (scatPinned != null){ const el = svg.querySelector(`circle.dot[data-i="${scatPinned}"]`); if (el) show(el); else scatPinned = null; }
}
