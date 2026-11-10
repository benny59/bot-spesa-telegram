"use strict";
// ---------- Week plan: UI ----------
const PLAN_ROWS = [
  ["kcal","Energy"],["p","Protein"],["c","Carbohydrate"],["fib","Fibre"],["f","Fat"],["n3","Omega-3"],
  ["sf","Saturated fat",1],["s","Sugars",1],["salt","Salt",1],
  ["vc","Vitamin C"],["va","Vitamin A"],["vd","Vitamin D"],["b12","Vitamin B12"],["fol","Folate"],["ca","Calcium"],["fe","Iron"],["mg","Magnesium"],["k","Potassium"],["zn","Zinc"]];
function renderRecTabs(){
  document.querySelectorAll("#recTabs button").forEach(b => b.setAttribute("aria-pressed", b.dataset.rt === recTab));
  for (const t of ["week","meal","kitchen","cooked"]) $("rp-"+t).hidden = t !== recTab;
}
$("recTabs").addEventListener("click", e => { const b = e.target.closest("button[data-rt]"); if (!b) return; recTab = b.dataset.rt; try { localStorage.setItem("bi-rectab", recTab); } catch(_){} renderRecTabs(); });
let sessForm = null;     // weekday index whose "add training" form is open
function renderWeekShape(){
  const start = planStart(), pd = planDays(start);
  const paceOpts = cur => [["busy","Quick"],["weekend","Relaxed"]].map(([k,n]) => `<option value="${k}"${k===cur?" selected":""}>${n}</option>`).join("");
  $("weekShape").innerHTML = `<div class="wk-head"><span></span><span>Cooking</span>${SLOTS.map(s=>`<span>${s.n}</span>`).join("")}</div>` + pd.map(w => `<div class="wk-day">
    <div class="wk-row">
      <span class="wd">${WD[w.wi]} <small>${esc(fmtDay(w.ds))}</small></span>
      <select data-wt="${w.wi}" aria-label="Cooking on ${WD[w.wi]}">${paceOpts(w.t === "weekend" ? "weekend" : "busy")}</select>
      ${SLOTS.map(s => `<button type="button" class="slot" data-ws="${w.wi}" data-sl="${s.k}" aria-pressed="${!!w[s.k]}" aria-label="${s.n} at home on ${WD[w.wi]}"><span class="lg">${s.n}</span><span class="sm">${s.n[0]}</span></button>`).join("")}</div>
    <div class="wk-sess">${(w.s||[]).map((x,si) => `<span class="sess s-${x.k}"><b>${esc(SESS[x.k]?.n||x.k)}</b> ${esc((WHEN[x.when]||"").replace(", after breakfast","").replace(", before dinner",""))} · ${Number(x.min)||SESS[x.k]?.min} min${x.note?` · ${esc(x.note)}`:""}<button type="button" class="x" data-sdel="${w.wi}-${si}" aria-label="Remove ${esc(SESS[x.k]?.n||"session")} on ${WD[w.wi]}">✕</button></span>`).join("") || `<span class="status">${trains() ? "Rest day" : ""}</span>`}
      <button type="button" class="xlink" data-sadd="${w.wi}">+ Training</button></div>
    ${sessForm === w.wi ? `<div class="sess-form">
      <label>Session<select id="sf-k">${Object.entries(SESS).map(([k,S])=>`<option value="${k}">${esc(S.n)}</option>`).join("")}</select></label>
      <label>When<select id="sf-when">${Object.entries(WHEN).map(([k,n])=>`<option value="${k}">${esc(n)}</option>`).join("")}</select></label>
      <label>Minutes<input type="number" id="sf-min" min="10" max="240" step="5" value="60"></label>
      <label>Note<input type="text" id="sf-note" maxlength="60" placeholder="optional, e.g. legs"></label>
      <div class="row"><button type="button" class="primary" data-ssave="${w.wi}">Add</button><button type="button" data-scancel="1">Cancel</button></div></div>` : ""}
  </div>`).join("");
  const opt = (id, key, list) => { $(id).innerHTML = list.map(([k,n]) => `<button type="button" data-k="${k}" aria-pressed="${planOpts[key]===k}">${n}</button>`).join(""); };
  opt("optStart","start",[["today","Today"],["tomorrow","Tomorrow"],["monday","Next Monday"]]);
  opt("optChange","change",[["close","Close to usual"],["balanced","Balanced"],["bold","Bold changes"]]);
  opt("optClimate","climate",[["0","No target"],["20","−20 %"],["40","−40 %"]]);
  if (document.activeElement !== $("athKg")) $("athKg").value = athlete.kg || "";
  const cov = pd.reduce((a,w)=>a+dayCov(w),0);
  const tk = pd.reduce((a,w)=>a+trainExtra(w.wi).kcal,0), nS = pd.reduce((a,w)=>a+(w.s||[]).length,0);
  $("weekCov").textContent = `${pd.reduce((a,w)=>a+SLOTS.filter(s=>w[s.k]).length,0)} meals at home plus snacks: about ${Math.round(cov/7*100)} % of the week's food for ${householdText()}.` + (trains() && nS ? ` ${nS} training sessions add about ${fmtInt(tk)} kcal for you this week, and raise your protein and carbohydrate on those days.` : "");
  $("planBtn").disabled = wpBusy || !cleanReceipts().length;
}
$("weekShape").addEventListener("change", e => { const i = e.target.dataset?.wt; if (i == null) return; week[+i] = {...week[+i], t: e.target.value}; saveWeekSoon(); });
$("weekShape").addEventListener("click", e => {
  const b = e.target.closest("button"); if (!b) return; const ds = b.dataset;
  if (ds.ws != null){ const i = +ds.ws, k = ds.sl; week[i] = {...week[i], [k]: week[i][k] ? 0 : 1}; renderWeekShape(); saveWeekSoon(); return; }
  if (ds.sadd != null){ sessForm = sessForm === +ds.sadd ? null : +ds.sadd; renderWeekShape(); const f = $("sf-k"); if (f){ f.focus(); f.onchange = () => { $("sf-min").value = SESS[f.value].min; }; } return; }
  if (ds.scancel){ sessForm = null; renderWeekShape(); return; }
  if (ds.ssave != null){ const i = +ds.ssave, k = $("sf-k").value; const x = {k, when: $("sf-when").value, min: Math.max(10, Math.min(240, Math.round(+$("sf-min").value || SESS[k].min)))}; const note = $("sf-note").value.trim().slice(0,60); if (note) x.note = note;
    week[i] = {...week[i], s: [...(week[i].s||[]), x]}; sessForm = null; renderWeekShape(); saveWeekSoon(); renderNutrition(); return; }
  if (ds.sdel){ const [i, si] = ds.sdel.split("-").map(Number); week[i] = {...week[i], s: (week[i].s||[]).filter((_,n)=>n!==si)}; renderWeekShape(); saveWeekSoon(); renderNutrition(); }
});
$("athKg").addEventListener("change", e => { const v = Math.round(parseFloat(e.target.value)); if (!(v >= 35 && v <= 200)){ e.target.value = athlete.kg; return; } athlete = {...athlete, kg: v}; renderWeekShape(); saveWeekSoon(); renderNutrition(); });
let wkTimer = null;
function saveWeekSoon(){ clearTimeout(wkTimer); wkTimer = setTimeout(() => saveSettings().catch(()=>{}), 500); }
for (const [id, key] of [["optStart","start"],["optChange","change"],["optClimate","climate"]])
  $(id).addEventListener("click", e => { const b = e.target.closest("button[data-k]"); if (!b) return; planOpts = {...planOpts, [key]: b.dataset.k}; renderWeekShape(); saveWeekSoon(); });
$("planBtn").onclick = async () => {
  wpBusy = true; $("planBtn").disabled = true; $("planStatus").className = "status"; $("planStatus").textContent = "Working out the week…";
  await new Promise(r => setTimeout(r, 30));
  try {
    const wp = solveWeek();
    if (!wp) throw {msg: "There isn't enough shopping in the last 90 days to plan from yet."};
    if (wp.error) throw {msg: "The plan couldn't be worked out this time. Try “Bold changes” or fewer meals at home."};
    weekPlan = wp; $("planStatus").textContent = "";
    renderWeekPlan(); $("wpResult").scrollIntoView({behavior:"smooth", block:"start"});
    if (db && uid) db.collection(COL).doc("weekplan").set(weekPlan).catch(()=>{});
  } catch(e){ $("planStatus").className = "status err"; $("planStatus").textContent = e?.msg || "Something went wrong working out the plan."; }
  finally { wpBusy = false; renderWeekShape(); }
};
function pctBar(p, u, lim){
  const mx = 160, w = Math.min(p, mx)/mx*100, uw = u != null ? Math.min(u, mx)/mx*100 : null;
  const bad = lim ? p > 105 : p < 90;
  return `<span class="pt"><i style="width:${w.toFixed(1)}%;background:${bad ? (lim ? "var(--up)" : "var(--nsC)") : "var(--down)"}"></i><b style="left:${(100/mx*100).toFixed(1)}%"></b>${uw != null ? `<u style="left:${uw.toFixed(1)}%" title="Your usual week ${Math.round(u)} %"></u>` : ""}</span>`;
}
function renderWeekPlan(){
  const box = $("wpResult");
  if (!weekPlan){ box.hidden = true; return; }
  box.hidden = false;
  const W = weekPlan, buy = W.items.filter(i => i.src === "buy"), kit = W.items.filter(i => i.src === "kitchen");
  const cost = buy.reduce((a,i)=>a+i.cost,0), pct = k => W.targets[k] ? W.tot[k]/W.targets[k]*100 : 0, upct = k => W.targets[k] ? W.usual[k]/W.targets[k]*100 : 0;
  const met = PLAN_ROWS.filter(([k,,lim]) => lim ? pct(k) <= 105 : pct(k) >= 90).length;
  const soonAll = buildPantry(21).filter(Q => Q.dl <= 6 && Q.dl >= 0 && Q.left > 20 && !Q.unknown && !Q.noNut && !PLAN_DROP.has(Q.ct)).length, soonUsed = kit.filter(i => i.soon).length;
  const co2 = W.tot.co2, dayKg = co2/1000/((W.tot.kcal||1)/2000), uDay = W.usual.kcal > 0 ? W.usual.co2/1000/(W.usual.kcal/2000) : 0;
  const byStore = {}; for (const i of buy) (byStore[i.store] ||= []).push(i);
  const stale = W.start < todayISO();
  $("wpMeta").textContent = `${WD[(d2(W.start).getUTCDay()+6)%7]} ${fmtDay(W.start)} – ${fmtDay(addDays(W.start,6))} · worked out ${new Date(W.at).toLocaleString("en-GB",{weekday:"short", hour:"2-digit", minute:"2-digit"})}`;
  $("wpTiles").innerHTML = `${stale ? `<p class="banner" style="margin:0 0 10px;grid-column:1/-1">This plan started on ${esc(fmtDay(W.start))}. Work it out again for the coming days.</p>` : ""}
    <div class="stat lead"><div class="k">Shopping</div><div class="v num">${eur(cost)}</div><div class="s">${W.usualCost > 0 ? `${cost <= W.usualCost ? eur(W.usualCost-cost)+" less than" : eur(cost-W.usualCost)+" more than"} your usual ${eur(W.usualCost)} for these meals` : "for the week"}</div></div>
    <div class="stat"><div class="k">Targets met</div><div class="v num">${met} of ${PLAN_ROWS.length}</div><div class="s">within 10 % of the household's needs, for the meals at home</div></div>
    <div class="stat"><div class="k">Climate</div><div class="v num">${fmtKg(co2)}</div><div class="s">CO₂e · ${dayKg.toLocaleString("de-DE",{minimumFractionDigits:1, maximumFractionDigits:1})} kg per 2,000 kcal${uDay > 0 ? `, ${dayKg <= uDay ? Math.round((1-dayKg/uDay)*100)+" % below" : Math.round((dayKg/uDay-1)*100)+" % above"} your usual ${uDay.toLocaleString("de-DE",{minimumFractionDigits:1, maximumFractionDigits:1})}` : ""}</div></div>
    <div class="stat"><div class="k">Use-soon food</div><div class="v num">${soonUsed} of ${soonAll}</div><div class="s">kitchen items near their shelf life go into the plan</div></div>`;
  let lastG = "";
  $("wpNut").innerHTML = `<div class="row" style="justify-content:space-between"><h3>The week against the targets</h3><div class="legend" style="margin:0"><span><i class="sw" style="background:var(--down)"></i>plan</span><span><i class="sw" style="background:var(--fg);width:3px"></i>100 %</span><span><i class="sw" style="background:var(--muted);width:3px;opacity:.6"></i>usual week</span></div></div>
    <div class="ptab">${PLAN_ROWS.map(([k,n,lim]) => `<div class="pr"><span>${esc(n)}${lim?' <span class="status">max</span>':""}</span>${pctBar(pct(k), upct(k), lim)}<span class="num ${lim ? (pct(k)>105?"up":"") : (pct(k)<90?"up":"")}">${Math.round(pct(k))} %</span></div>`).join("")}
      ${W.longT ? `<div class="grp">Longevity food groups</div>` + LONG.map(L => { const t = W.longT[L.k]*1000, pv = (W.longP[L.k]||0)/t*100, uv = (W.longU[L.k]||0)/t*100;
        return `<div class="pr"><span>${esc(L.n)}${L.max?' <span class="status">max</span>':""}</span>${pctBar(pv, uv, !!L.max)}<span class="num ${L.max ? (pv>105?"up":"") : (pv<90?"up":"")}">${fmtGrams(W.longP[L.k]||0)}</span></div>`; }).join("")
        + `<div class="pr"><span>Plant share of protein</span>${pctBar(W.plantShare*200, W.plantShareU*200)}<span class="num ${W.plantShare<0.45?"up":""}">${Math.round(W.plantShare*100)} %</span></div>` : ""}</div>
    <p class="note" style="margin-top:8px">Targets are your household's reference intakes (${esc(householdText())}) for the share of the week eaten at home, ${Math.round(W.covSum/7*100)} %. Food groups are per adult per day (a child counts as their age's share of an adult): vegetables 400 g, fruit 250 g, legumes 100 g cooked, whole grains 90 g, nuts and seeds 25 g, fish about 200 g a week, at most 300 g of meat a week with red and processed meat kept low, and at least half the protein from plants. Their 100 % mark is the target; for limits, staying under it. The usual week is what you've bought on average over the last 90 days.</p>`;
  $("wpShop").innerHTML = `<div class="row" style="justify-content:space-between"><h3>Shopping list</h3><button type="button" id="wpCopy">Copy list</button></div>
    ${Object.entries(byStore).sort((a,b)=>b[1].length-a[1].length).map(([st, l]) => `<div class="pgroup"><h3>${esc(st)} <span class="status">${eur(l.reduce((a,i)=>a+i.cost,0))}</span></h3>${l.sort((a,b)=>a.cat.localeCompare(b.cat)).map(i => `<div class="shop"><span>${i.weighed ? fmtGrams(i.g) : i.packs+" ×"} ${esc(i.name)}${i.bio?" ·bio":""}${i.isNew?' <span class="chip fb">new for you</span>':""}<small>${esc(i.rname||"")}${i.size?" · "+esc(i.size):""}${i.habit > 0 ? ` · usually ${fmtGrams(i.habit*1000)} a week` : ""}</small></span><span class="num">${eur(i.cost)}</span></div>`).join("")}</div>`).join("") || `<p class="empty">Nothing to buy: the kitchen covers the week.</p>`}
    ${kit.length ? `<div class="pgroup"><h3>From your kitchen</h3>${kit.sort((a,b)=>a.dl-b.dl).map(i => `<div class="shop"><span>${fmtGrams(i.g)} ${esc(i.name)}${i.bio?" ·bio":""}</span>${dueChip(i.dl)}</div>`).join("")}</div>` : ""}
    <p class="note" style="margin-top:6px">Each product comes from the shop where you've paid least for it per kg. Amounts are rounded to whole packs. Products are limited to ${{close:"1.3 times",balanced:"twice",bold:"three times"}[W.opts.change]} what you usually buy and to 15 % of the week's energy each, so the plan stays like your own shopping.</p>`;
  renderMenu();
}
$("wpShop").addEventListener("click", async e => {
  if (e.target.id !== "wpCopy" || !weekPlan) return;
  const byStore = {}; for (const i of weekPlan.items.filter(i => i.src === "buy")) (byStore[i.store] ||= []).push(`${i.weighed ? fmtGrams(i.g) : i.packs+" ×"} ${i.name}${i.bio?" (organic)":""}`);
  const txt = Object.entries(byStore).map(([s,l]) => s + "\n" + l.map(x => "- " + x).join("\n")).join("\n\n");
  try { await navigator.clipboard.writeText(txt); e.target.textContent = "Copied"; } catch(_){ e.target.textContent = "Couldn't copy"; }
  setTimeout(() => { if (e.target.isConnected) e.target.textContent = "Copy list"; }, 2500);
});
// ---------- Menu for the week, written by Claude from the planned basket ----------
function menuPrompt(W){
  const kids = ((household.c13||0)+(household.c46||0)+(household.c710||0)) > 0, baby = (household.baby||0) > 0;
  const st = STYLES.find(x => x.k === plan.style) || STYLES[0];
  const basket = W.items.map((i, n) => `k${n+1} | ${i.name}${i.bio?" (organic)":""} | ${i.g} g | ${i.src === "kitchen" ? (i.soon ? "in the kitchen, USE EARLY IN THE WEEK" : "in the kitchen") : "to buy"}`).join("\n");
  const dayLines = W.days.map(d => { const wi = (d2(d.ds).getUTCDay()+6)%7, ss = d.s || [];
    return `${d.ds} (${WD[wi]}), ${d.t === "weekend" ? "time to cook" : "busy, quick cooking"}; meals at home: ${SLOTS.filter(s=>d[s.k]).map(s=>s.meal).join(", ") || "none"}${W.train ? `; athlete's training: ${ss.length ? ss.map(sessText).join(" + ") : "rest"}. Meal roles: ${rolesText(wi, ss)}` : ""}`; }).join("\n");
  return `Write a week's menu for a household in Germany (${householdText()}), using this planned basket. It was optimised for cost and nutrition, so use nearly all of it, roughly in these amounts across the week.
Basket (id | food | grams for the week | status):
${basket}
Meals at home:
${dayLines}
${W.train ? `One adult trains (about ${W.train.kg} kg); nobody else does. Shape that person's portions to the meal roles (bigger portion or an extra protein side such as skyr, eggs, tofu or fish at recovery meals) while the rest of the family eats the same dish normally. Training adds about ${W.train.kcal} kcal at home this week, already in the basket.\n` : ""}${LONG_PROMPT}
Style: ${st.n}. ${st.note} Original dishes; don't reproduce published recipes or name chefs or sites in titles.
${kids ? "For young children: mild, little added salt, whole nuts chopped or ground, round foods quartered.\n" : ""}${baby ? "The baby doesn't eat from the family shopping yet.\n" : ""}Basics you can assume: salt, pepper, oils, vinegar, mustard, stock, garlic, onions, flour, sugar, soy sauce${spiceShelf ? ", and their spice shelf: " + spiceShelf : ""}. Cook once, eat twice where it helps (weekend dishes feeding a weekday lunch). Use kitchen items marked USE EARLY in the first days. Snacks can be listed per day as one short line.
Reply with only JSON: {"days":[{"date":"YYYY-MM-DD","meals":[{"slot":"breakfast|lunch|dinner","title":"","summary":"one sentence","minutes":20,"uses":[{"id":"k3","g":200}]}],"snack":""}]}
"g" is grams for the whole household at that meal.`;
}
async function writeMenu(){
  if (!sample || !weekPlan) return;
  wpCtl = new AbortController(); $("menuBtn").disabled = true; $("menuStop").hidden = false; $("menuStatus").className = "status";
  $("menuStatus").textContent = "Writing the week's menu… about a minute.";
  try {
    let out;
    try { out = await sample.json(menuPrompt(weekPlan), {signal: wpCtl.signal}); }
    catch(e){
      if (e?.code !== "invalid_json") throw e;
      const half = (a, b) => ({...weekPlan, days: weekPlan.days.slice(a, b)});
      const [x, y] = [await sample.json(menuPrompt(half(0,4)), {signal: wpCtl.signal}), await sample.json(menuPrompt(half(4,7)), {signal: wpCtl.signal})];
      out = {days: [...(x?.days||[]), ...(y?.days||[])]};
    }
    const daysOut = (out?.days || []).filter(d => d && Array.isArray(d.meals));
    if (!daysOut.length) throw {code:"empty"};
    weekPlan = {...weekPlan, menu: {style: plan.style, days: daysOut.map(d => ({date: String(d.date||""), snack: String(d.snack||""), meals: d.meals.filter(m => m && m.title).map(m => ({slot: m.slot, title: String(m.title), summary: String(m.summary||""), minutes: Number(m.minutes)||0, uses: (m.uses||[]).filter(u => /^k\d+$/.test(u.id)).map(u => ({id:u.id, g: Math.max(0, Number(u.g)||0)}))}))}))}};
    $("menuStatus").textContent = "";
    if (db && uid) db.collection(COL).doc("weekplan").set(weekPlan).catch(()=>{});
    renderMenu();
  } catch(e){
    $("menuStatus").className = "status err";
    $("menuStatus").textContent = e?.code === "cancelled" ? "Stopped." : e?.code === "not_granted" ? "The menu needs your permission to use Claude on this page." : "The menu didn't come through. Try again.";
    if (e?.code === "cancelled") $("menuStatus").className = "status";
  } finally { $("menuBtn").disabled = !sample; $("menuStop").hidden = true; }
}
function mealMetrics(m){
  const tot = {}; for (const k of [...PLAN_KEYS, ...PLAN_MIC]) tot[k] = 0; let cost = 0; const ings = [];
  for (const u of m.uses){ const it = weekPlan.items[+u.id.slice(1)-1]; if (!it) continue; const kg = u.g/1000;
    for (const k of PLAN_KEYS) tot[k] += (it.a[k]||0)*kg; for (const k of PLAN_MIC) tot[k] += (it.m[k]||0)*kg;
    const c = (it.ppk||0)*kg; cost += c; ings.push({it, g: u.g, cost: c}); }
  return {tot, cost, ings};
}
function renderMenu(){
  const W = weekPlan, box = $("wpMenu");
  $("menuBtn").disabled = !sample; $("menuBtn").textContent = W?.menu ? "Write it again" : "Write the menu";
  if (!W?.menu){ box.innerHTML = `<p class="note" style="margin:0">Claude turns this basket into a week of ${esc((STYLES.find(x=>x.k===plan.style)||STYLES[0]).n)} dishes that fit each kind of day (style is set under One meal). Methods are written when you open a dish.</p>`; return; }
  const portions = portionsFor("family"), openIds = [...box.querySelectorAll("details[open]")].map(d => d.dataset.mm);
  box.innerHTML = W.menu.days.map((d, di) => `<div class="mday"><h4>${esc(d.date ? WD[(d2(d.date).getUTCDay()+6)%7] + " " + fmtDay(d.date) : "Day "+(di+1))} <span class="status">${esc((W.days[di]?.s||[]).map(x => SESS[x.k]?.n).filter(Boolean).join(" + ") || (W.train ? "rest day" : ""))}</span></h4>
    ${d.meals.map((m, mi) => { const x = mealMetrics(m); const id = `${di}-${mi}`;
      return `<details class="mmeal" data-mm="${id}"><summary><span class="sl">${esc((SLOTS.find(s=>s.meal===m.slot)||{n:m.slot}).n)}</span><b>${esc(m.title)}</b><small>${m.minutes ? m.minutes+" min · " : ""}${eur(x.cost/portions)} · ${fmtInt(x.tot.kcal/portions)} kcal · ${Math.round(x.tot.p/portions)} g protein · ${fmtInt(x.tot.co2/portions)} g CO₂e per adult portion</small></summary>
        <div class="mbody">${m.summary ? `<p class="why">${esc(m.summary)}</p>` : ""}<ul>${x.ings.map(g => `<li>${fmtGrams(g.g)} ${esc(g.it.name)} <span class="src">· ${g.it.src === "kitchen" ? "from your kitchen" : "from the list"}</span></li>`).join("")}</ul>
        <div class="msteps" id="ms-${id}">${m.steps ? `<ol>${m.steps.map(s=>`<li>${esc(s)}</li>`).join("")}</ol>${m.kid ? `<p class="note"><b>For the little one:</b> ${esc(m.kid)}</p>` : ""}` : `<button type="button" data-steps="${id}">Show the method</button>`}</div>
        <div class="acts">${m.cooked ? `<span class="ok">✓ Logged ${esc(weekday(m.cooked))}, under Cooked</span>` : `<button type="button" class="primary" data-pcook="${id}">We cooked this</button>`}<span class="status" id="pc-${id}"></span></div></div></details>`; }).join("")}
    ${d.snack ? `<p class="note" style="margin:4px 0 0"><b>Snacks:</b> ${esc(d.snack)}</p>` : ""}</div>`).join("");
  for (const id of openIds){ const d = box.querySelector(`details[data-mm="${id}"]`); if (d) d.open = true; }
}
$("menuBtn").onclick = writeMenu;
$("menuStop").onclick = () => wpCtl?.abort();
$("wpMenu").addEventListener("click", async e => {
  const sid = e.target.dataset?.steps;
  if (sid){
    const [di, mi] = sid.split("-").map(Number), m = weekPlan.menu.days[di].meals[mi], x = mealMetrics(m);
    e.target.disabled = true; e.target.textContent = "Writing the method…";
    try {
      const kids = ((household.c13||0)+(household.c46||0)+(household.c710||0)) > 0;
      const out = await sample.json(`Write the method for "${m.title}" (${m.summary}) for ${householdText()}, style: ${(STYLES.find(x=>x.k===weekPlan.menu.style)||STYLES[0]).n}. Ingredients for everyone: ${x.ings.map(g => `${g.g} g ${g.it.name}`).join(", ")}, plus basics (salt, pepper, oil, garlic, onion, spices${spiceShelf ? ": " + spiceShelf : ""}). Precise steps with times and visual cues.${kids ? " Add one line on serving young children (mild, quartered round foods, chopped nuts)." : ""} Reply with only JSON: {"steps":["",""],"kid":""}`, {});
      m.steps = (out?.steps || []).map(String).slice(0, 14); m.kid = String(out?.kid || "");
      if (db && uid) db.collection(COL).doc("weekplan").set(weekPlan).catch(()=>{});
      renderMenu();
    } catch(_){ e.target.disabled = false; e.target.textContent = "Couldn't write it. Try again"; }
    return;
  }
  const cid = e.target.dataset?.pcook; if (!cid) return;
  const b = e.target;
  if (b.dataset.armed !== "1"){ b.dataset.armed = "1"; b.textContent = "Confirm: log it"; $("pc-"+cid).textContent = "This takes the amounts out of your kitchen."; setTimeout(()=>{ if (b.isConnected && b.dataset.armed){ b.dataset.armed = ""; b.textContent = "We cooked this"; } }, 6000); return; }
  b.disabled = true;
  const [di, mi] = cid.split("-").map(Number), m = weekPlan.menu.days[di].meals[mi], x = mealMetrics(m), portions = portionsFor("family");
  const pantry = buildPantry(30), usedG = usedByMeals();
  const uses = x.ings.map(g => {
    const P = pantry.find(q => q.key === g.it.key); let need = g.g; const lines = [];
    if (P) for (const l of P.lines){ if (need <= 0) break; if (l.g == null){ lines.push({ref:l.ref, g:need}); need = 0; break; } const take = Math.min(Math.max(0, l.g - (usedG[l.ref]||0)), need); if (take > 0){ lines.push({ref:l.ref, g:Math.round(take)}); need -= take; } }
    return {key: g.it.key, name: g.it.name, g: Math.round(g.g), lines};
  });
  const per = k => x.tot[k]/portions;
  const meal = {kind:"meal", id:"meal-"+Date.now().toString(36), date: todayISO(), day: ({strength:"strength", z2:"z2", cardio:"z2", yoga:"yoga", wp:"wp", game:"game"})[(weekPlan.days[di]?.s||[])[0]?.k] || weekPlan.days[di]?.t || "busy", meal: m.slot, who:"family", title: m.title, portions, fromPlan: true,
    perAdult: {kcal: per("kcal"), p: per("p"), c: per("c"), f: per("f"), fib: per("fib"), sf: per("sf"), s: per("s"), salt: per("salt"), co2: per("co2")}, cost: x.cost, perCost: x.cost/portions,
    nrf: nrfOf({...x.tot, mic: Object.fromEntries(PLAN_MIC.map(k => [k, x.tot[k]])), kg: x.ings.reduce((a,g)=>a+g.g,0)/1000}),
    uses, recipe: {title: m.title, summary: m.summary, ingredients: x.ings.map(g => ({name: g.it.name, g: Math.round(g.g), src: g.it.src})), steps: m.steps || [], kid: m.kid || ""}, savedAt: new Date().toISOString()};
  try {
    m.cooked = todayISO();
    if (db && uid){ await db.collection(COL).doc(meal.id).set(meal); db.collection(COL).doc("weekplan").set(weekPlan).catch(()=>{}); } else { meals.push(meal); renderAll(); }
    renderMenu();
  }
  catch(_){ delete m.cooked; b.disabled = false; b.dataset.armed = ""; b.textContent = "We cooked this"; $("pc-"+cid).textContent = "Couldn't log it just now."; }
});
function renderWeek(){ renderRecTabs(); renderWeekShape(); renderWeekPlan(); }
