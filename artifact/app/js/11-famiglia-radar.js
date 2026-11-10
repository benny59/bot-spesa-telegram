"use strict";
// ---- Weekly radar against reference intakes ----
let radWeek = "avg";
// Household: each member counts as a share of an adult's daily reference, nutrient by nutrient
// (German Nutrition Society reference values for the age group ÷ EU adult reference intakes).
// Babies fed breast milk or formula eat nothing from the shopping, so they count as zero.
const MEMBERS = [
  {k:"adult", n:"Adults",          f:{}},
  {k:"c13",   n:"Children 1–3",    f:{kcal:.55,p:.28,c:.55,f:.55,sf:.55,s:.55,salt:.33,fib:.33,vc:.25,va:.375,vd:1,b12:.4,fol:.6,ca:.75,fe:.57,mg:.21,k:.55,zn:.3,n3:.5}},
  {k:"c46",   n:"Children 4–6",    f:{kcal:.68,p:.36,c:.68,f:.68,sf:.68,s:.68,salt:.5,fib:.47,vc:.375,va:.44,vd:1,b12:.6,fol:.7,ca:.94,fe:.57,mg:.32,k:.65,zn:.4,n3:.65}},
  {k:"c710",  n:"Children 7–10",   f:{kcal:.88,p:.5,c:.88,f:.88,sf:.88,s:.88,salt:.75,fib:.6,vc:.56,va:.56,vd:1,b12:.72,fol:1,ca:1.13,fe:.71,mg:.45,k:.9,zn:.6,n3:.85}},
  {k:"baby",  n:"Babies (breast or bottle fed)", f:null},
];
let household = {adult:1, c13:0, c46:0, c710:0, baby:0};
function famFactor(k){ let t = 0; for (const m of MEMBERS){ const n = household[m.k]||0; if (!n || !m.f) continue; t += n * (m.k==="adult" ? 1 : (m.f[k] ?? m.f.kcal)); } return t; }
const ADULT_DAY = {n3:1.4, kcal:2000, p:50, c:260, fib:30, f:70, sf:20, s:90, salt:5, vc:80, va:800, vd:5, b12:2.5, fol:200, ca:800, fe:14, mg:375, k:2000, zn:10};
function famDay(k){ return ADULT_DAY[k]*famFactor(k) + ((k === "kcal" || k === "p" || k === "c") ? trainAvg(k) : 0); }
// Family reference per 1,000 kcal of food: what the household needs of a nutrient relative to its energy need.
function famPer1000(k){ const e = famDay("kcal"); return e > 0 ? famDay(k)/e*1000 : ADULT_DAY[k]/2; }
function householdText(){
  const parts = MEMBERS.filter(m => household[m.k] > 0).map(m => `${household[m.k]} ${m.k==="adult" ? (household[m.k]===1?"adult":"adults") : m.k==="baby" ? (household[m.k]===1?"baby":"babies") : (household[m.k]===1?"child ":"children ")+m.n.replace("Children ","")}`);
  return parts.join(", ") || "nobody";
}
function householdForm(){
  return `<div class="row" style="gap:6px 14px">${MEMBERS.map(m => `<label class="chk" for="hh-${m.k}">${esc(m.n)} <input type="number" id="hh-${m.k}" data-hh="${m.k}" min="0" max="10" step="1" value="${household[m.k]||0}" style="width:3.6em"></label>`).join("")}</div>`;
}
const RAD = [
  {k:"kcal", n:"Energy",       s:"Energy",  ref:2000, u:"kcal", g:"Energy & macronutrients"},
  {k:"p",    n:"Protein",      s:"Protein", ref:50,   u:"g", g:"Energy & macronutrients"},
  {k:"c",    n:"Carbohydrate", s:"Carbs",   ref:260,  u:"g", g:"Energy & macronutrients"},
  {k:"fib",  n:"Fibre",        s:"Fibre",   ref:30,   u:"g", g:"Energy & macronutrients"},
  {k:"f",    n:"Fat",          s:"Fat",     ref:70,   u:"g", g:"Energy & macronutrients"},
  {k:"n3",   n:"Omega-3 fats", s:"Omega-3", ref:1.4,  u:"g", g:"Energy & macronutrients"},
  {k:"sf",   n:"Saturated fat",s:"Sat. fat",ref:20,   u:"g", lim:true, g:"Upper limits"},
  {k:"s",    n:"Sugars",       s:"Sugars",  ref:90,   u:"g", lim:true, g:"Upper limits"},
  {k:"salt", n:"Salt",         s:"Salt",    ref:5,    u:"g", lim:true, g:"Upper limits"},
  ...MIC.map(m => ({k:m.k, n:m.n, s:m.n.replace("Vitamin ","Vit. "), ref:m.nrv, u:m.u, mic:true, g: ["ca","fe","mg","k","zn"].includes(m.k) ? "Minerals" : "Vitamins"})),
];
function weekStart(ds){ const d = d2(ds); const wd = (d.getUTCDay()+6)%7; d.setUTCDate(d.getUTCDate()-wd); return d.toISOString().slice(0,10); }
function addDays(ds, n){ const d = d2(ds); d.setUTCDate(d.getUTCDate()+n); return d.toISOString().slice(0,10); }
function weeklyTotals(){
  const weeks = {}; let food = 0, counted = 0;
  for (const r of cleanReceipts()){
    const wk = weekStart(r.date), W = (weeks[wk] ||= {n:0, ...Object.fromEntries(RAD.map(a=>[a.k,0]))});
    W.n++;
    for (const it0 of r.items){
      const it = withLib(r, it0); if (!isFood(it)) continue;
      food += it.price; const ln = lineNutrition(it); if (!ln) continue; counted += it.price;
      for (const a of RAD) W[a.k] += a.mic ? (ln.mic?.[a.k] || 0) : ln[a.k];
    }
  }
  return {weeks, cover: food ? counted/food : 0};
}
function renderRadar(){
  const card = $("nutRadar");
  const {weeks, cover} = weeklyTotals();
  const keys = Object.keys(weeks).sort();
  if (!keys.length){ card.hidden = true; return; }
  const first = keys[0], lastWk = keys[keys.length-1];
  const nWeeks = Math.round((d2(lastWk) - d2(first))/(7*864e5)) + 1;
  const avg = Object.fromEntries(RAD.map(a => [a.k, keys.reduce((s,k)=>s+weeks[k][a.k],0)/nWeeks]));
  if (radWeek !== "avg" && !weeks[radWeek]) radWeek = "avg";
  const cur = radWeek === "avg" ? avg : weeks[radWeek];
  const pctOf = (src, a) => { const ref = famDay(a.k)*7; return ref > 0 ? src[a.k] / ref * 100 : 0; };
  const today = new Date().toISOString().slice(0,10);
  const shown = keys.slice(-8);
  // geometry
  const maxSeen = Math.max(...RAD.map(a => pctOf(cur,a)), radWeek !== "avg" ? Math.max(...RAD.map(a => pctOf(avg,a))) : 0);
  const S = 360, cx = S/2, cy = S/2, Rm = 118, MAXP = Math.min(200, Math.max(150, Math.ceil(maxSeen/50)*50)), N = RAD.length;
  const ang = i => -Math.PI/2 + i*2*Math.PI/N;
  const pt = (i, p) => { const r = Math.min(p, MAXP)/MAXP*Rm; return [cx + r*Math.cos(ang(i)), cy + r*Math.sin(ang(i))]; };
  let g = "";
  for (let ring = 50; ring <= MAXP; ring += 50){
    const pts = RAD.map((_,i)=>pt(i,ring).map(v=>v.toFixed(1)).join(",")).join(" ");
    g += `<polygon points="${pts}" fill="none" stroke="${ring===100?"var(--fg)":"var(--grid)"}" stroke-width="${ring===100?1.4:1}" ${ring===100?'stroke-dasharray="4 3"':""}/>`;
  }
  RAD.forEach((a,i) => { const [x,y] = pt(i,MAXP); g += `<line x1="${cx}" y1="${cy}" x2="${x.toFixed(1)}" y2="${y.toFixed(1)}" stroke="var(--grid)"/>`; });
  for (const ring of [100, MAXP]){ const [x,y] = pt(0,ring); g += `<text class="ring" x="${(x+4).toFixed(1)}" y="${(y+10).toFixed(1)}">${ring} %</text>`; }
  const poly = (src, attrs) => `<polygon points="${RAD.map((a,i)=>pt(i,pctOf(src,a)).map(v=>v.toFixed(1)).join(",")).join(" ")}" ${attrs}/>`;
  if (radWeek !== "avg") g += poly(avg, `fill="none" stroke="var(--muted)" stroke-width="1.2" stroke-dasharray="3 3"`);
  g += poly(cur, `fill="var(--s1)" fill-opacity=".22" stroke="var(--s1)" stroke-width="2" stroke-linejoin="round"`);
  RAD.forEach((a,i) => { const p = pctOf(cur,a), [x,y] = pt(i,p), over = p > MAXP;
    const bad = a.lim ? p > 100 : p < 66;
    g += `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${over?4:3}" fill="${bad?(a.lim?"var(--up)":"var(--surface)"):"var(--s1)"}" stroke="${a.lim&&p>100?"var(--up)":"var(--s1)"}" stroke-width="1.5"><title>${esc(a.n)}: ${Math.round(p)} % of the weekly reference</title></circle>`;
    const [lx,ly] = pt(i, MAXP+34), anchor = Math.abs(lx-cx) < 8 ? "middle" : lx > cx ? "start" : "end";
    const [tx,ty] = [cx + (Rm+14)*Math.cos(ang(i)), cy + (Rm+14)*Math.sin(ang(i))];
    g += `<text x="${tx.toFixed(1)}" y="${(ty+3.5).toFixed(1)}" text-anchor="${anchor}" class="${a.lim?"lim":""}">${esc(a.s)}${a.lim?" (max)":""}</text>`;
  });
  const chips = [`<button type="button" id="rw-avg" data-rw="avg" aria-pressed="${radWeek==="avg"}">Average week</button>`]
    .concat(shown.map(k => `<button type="button" id="rw-${k}" data-rw="${k}" aria-pressed="${radWeek===k}">${fmtDay(k)}${addDays(k,6) >= today ? " (now)" : ""}</button>`)).join("");
  let lastG = "";
  const list = RAD.map(a => { const p = pctOf(cur,a), amt = cur[a.k];
    const head = a.g !== lastG ? `<div class="grp">${esc(a.g)}</div>` : ""; lastG = a.g;
    const fmtA = amt >= 1000 ? fmtInt(amt) : amt >= 10 ? Math.round(amt).toString() : amt.toLocaleString("de-DE",{maximumFractionDigits:1});
    const cl = a.lim ? (p > 100 ? "up" : "") : (p < 66 ? "up" : p >= 100 ? "down" : "");
    return head + `<div class="rl"><span>${esc(a.n)}${a.lim?' <span class="status">max</span>':""}</span><span>${fmtA} ${esc(a.u)}</span><span class="${cl}">${Math.round(p)} %</span></div>`; }).join("");
  const wkLabel = radWeek === "avg" ? `Average over ${nWeeks} week${nWeeks>1?"s":""} (${fmtDay(first)} – ${fmtDay(addDays(lastWk,6))})` : `Week of ${fmtDay(radWeek)} – ${fmtDay(addDays(radWeek,6))} · ${weeks[radWeek].n} receipt${weeks[radWeek].n>1?"s":""}${addDays(radWeek,6) >= today ? " · still in progress" : ""}`;
  card.innerHTML = `<div class="row" style="justify-content:space-between;margin-bottom:8px"><h3>Your week against the reference</h3>
      </div>
    <details style="margin-bottom:8px"><summary class="status" style="font-weight:500">Household: ${esc(householdText())} · change</summary><div style="margin-top:8px">${householdForm()}</div></details>
    <div class="chips" id="radWeeks" role="group" aria-label="Week">${chips}</div>
    <p class="status" style="margin:8px 0 4px">${esc(wkLabel)}</p>
    <div class="radar-wrap">
      <svg class="radar" viewBox="-36 0 ${S+72} ${S}" role="img" aria-label="Radar chart of nutrients bought as a percentage of the weekly reference">${g}</svg>
      <div class="rlist"><div class="rl hd"><span>Nutrient</span><span>Bought</span><span>of ref.</span></div>${list}</div>
    </div>
    <p class="note" style="margin-top:10px">The dashed ring is 100 %: one week of what your household needs (${esc(householdText())}): EU reference intakes for adults, scaled for children with the German Nutrition Society's values for their age, about ${fmtInt(famDay("kcal"))} kcal a day in all. Babies fed breast milk or formula count as zero until they eat from the family shopping. Saturated fat, sugars and salt are upper limits, so for those staying inside the ring is the aim; points beyond ${MAXP} % sit on the edge. ${radWeek!=="avg"?"The grey dashed outline is your average week. ":""}It shows what was bought that week, not what was eaten: a big shop or a week of eating out moves it a lot, so the average week is the steadier view.${cover < 0.95 ? ` ${Math.round((1-cover)*100)} % of food spending has no nutrition values (such as counter slips) and isn't included.` : ""}</p>`;
  $("radWeeks").addEventListener("click", e => { const b = e.target.closest("button[data-rw]"); if (!b) return; radWeek = b.dataset.rw; renderRadar(); });
  card.querySelectorAll("input[data-hh]").forEach(inp => inp.addEventListener("change", e => {
    const v = Math.max(0, Math.min(10, Math.round(parseFloat(e.target.value)||0))); household = {...household, [e.target.dataset.hh]: v};
    renderNutrition(); saveSettings(); }));
}
