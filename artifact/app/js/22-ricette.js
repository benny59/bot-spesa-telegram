"use strict";
// =====================================================================
// Recipes on demand
// =====================================================================
const DAYS = [
  {k:"pre",      n:"Before training",    note:"1½–3 hours before training: plenty of easily digested carbohydrate, some protein, little fat and fibre so it sits well.", t:{c:[60,null], p:[15,35], f:[null,18], fib:[null,8]}},
  {k:"strength", n:"After strength",     note:"Within a couple of hours after lifting: 30–40 g protein per adult with carbohydrate to refill.", t:{p:[30,45], c:[50,null]}},
  {k:"z2",       n:"After zone 2 cardio",note:"Easy endurance burns mostly fat: moderate carbohydrate, 20–35 g protein, lots of vegetables.", t:{p:[20,35], c:[40,90], fib:[8,null]}},
  {k:"yoga",     n:"Yoga or rest day",   note:"Lighter and plant-forward: less energy, high fibre, omega-3 and colourful vegetables.", t:{kcal:[null,650], fib:[10,null]}},
  {k:"wp",       n:"After water polo",   note:"A long, intense session: 30–40 g protein for the player, plenty of carbohydrate to refill, and something salty to drink. Late at night, keep it easy to digest.", t:{p:[30,45], c:[70,null], f:[null,25]}},
  {k:"game",     n:"Match day",          note:"Familiar, carbohydrate-rich food; the last proper meal 3–4 hours before the game, low in fat and fibre, then easy carbohydrate 1–2 hours before.", t:{c:[70,null], p:[20,35], f:[null,20], fib:[null,8]}},
  {k:"busy",     n:"Busy weekday",       note:"On the table in about 20 minutes, with little washing up.", t:{}},
  {k:"weekend",  n:"Weekend cooking",    note:"Time to cook together, and dishes that stretch into tomorrow's lunch.", t:{}},
];
const MEALS = [{k:"breakfast", n:"Breakfast", f:0.8}, {k:"lunch", n:"Lunch", f:1}, {k:"dinner", n:"Dinner", f:1}, {k:"snack", n:"Snack", f:0.45}];
const WHO = [{k:"family", n:"Family"}, {k:"adults", n:"Adults only"}, {k:"me", n:"Just me"}];
const STYLES = [
  {k:"gourmet", n:"Gourmet, Ottolenghi spirit", note:"Bold, layered and generous: herbs by the handful, a sharp note of lemon, sumac or pickle, contrasting textures, a cool yogurt or tahini sauce, and a finish of toasted nuts, seeds, pomegranate or chilli oil. Original recipes, inspired by his way of cooking."},
  {k:"italian", n:"Italian, GialloZafferano style", note:"Classic Italian home cooking the way an Italian family makes it: a proper soffritto, pasta cooked al dente and finished in the pan with its water, creamy risotto, few ingredients treated with respect, and regional dishes. Original recipes in that style."},
  {k:"everyday", n:"Everyday", note:"Simple, familiar home cooking with few steps."},
  {k:"kids", n:"Kid favourites", note:"Food young children will happily eat, with a grown-up topping on the side."},
];
let spiceShelf = "";
try { spiceShelf = localStorage.getItem("bi-spices") || ""; } catch(_){}
let settingsDoc = null;
const TIMES = [{k:"20", n:"About 20 min"}, {k:"40", n:"Up to 40 min"}, {k:"any", n:"No limit"}];
const REC_COLORS = ["var(--s1)","var(--s2)","var(--s3)"];
const plan = (() => { const h = new Date().getHours(), wd = new Date().getDay();
  let style = "gourmet"; try { style = localStorage.getItem("bi-style") || "gourmet"; } catch(_){}
  return {style, day: (wd===0||wd===6) ? "weekend" : "busy", meal: h < 10 ? "breakfast" : h < 15 ? "lunch" : h < 17 ? "snack" : "dinner", who:"family", time: (wd===0||wd===6) ? "any" : "20"}; })();
let recState = null, recCtl = null;
try { const c = JSON.parse(localStorage.getItem("bi-recipes")||"null"); if (c && c.recipes) recState = c; } catch(_){}
function portionsFor(who){
  if (who === "me") return 1;
  if (who === "adults") return Math.max(1, household.adult||1);
  let p = household.adult||0; for (const m of MEMBERS){ if (m.k==="adult" || !m.f) continue; p += (household[m.k]||0)*m.f.kcal; }
  return Math.max(1, Math.round(p*10)/10);
}
function whoText(who){
  if (who === "me") return "one adult";
  if (who === "adults") return `${household.adult||1} adult${(household.adult||1)>1?"s":""}`;
  return householdText();
}
function chipRow(id, opts, cur){ $(id).innerHTML = opts.map(o => `<button type="button" id="${id}-${o.k}" data-k="${o.k}" aria-pressed="${o.k===cur}">${esc(o.n)}</button>`).join(""); }
function renderPlan(){
  chipRow("dayChips", DAYS, plan.day); chipRow("mealChips", MEALS, plan.meal); chipRow("whoChips", WHO, plan.who); chipRow("timeChips", TIMES, plan.time); chipRow("styleChips", STYLES, plan.style);
  $("styleNote").textContent = (STYLES.find(x=>x.k===plan.style)||STYLES[0]).note;
  if (document.activeElement !== $("spiceShelf")) $("spiceShelf").value = spiceShelf;
  const d = DAYS.find(x=>x.k===plan.day), sg = suggestToday();
  $("dayNote").textContent = d.note + (trains() && sg.ss.length ? ` Your week says ${WD[sg.wi]}: ${sg.ss.map(sessText).join("; ")}.` : "");
  const pantry = buildPantry(Math.max(pantryWin, 14));
  const pinList = [...pins].map(k => pantry.find(p=>p.key===k) || {key:k, name: k.split("|")[0], missing:true});
  $("pinField").hidden = !pinList.length;
  $("pinChips").innerHTML = pinList.map(p => `<button type="button" data-unpin="${esc(p.key)}" aria-label="Remove ${esc(p.name)}">${esc(p.name)}${p.missing?" (to buy)":""} ✕</button>`).join("");
  $("suggestBtn").disabled = !sample;
  const NOSAMPLE = "Suggestions need Claude on this page, which isn't available in this view.";
  if (!sample && !$("suggestStatus").textContent) $("suggestStatus").textContent = NOSAMPLE;
  else if (sample && $("suggestStatus").textContent === NOSAMPLE) $("suggestStatus").textContent = "";
}
for (const [id, key] of [["dayChips","day"],["mealChips","meal"],["whoChips","who"],["timeChips","time"],["styleChips","style"]])
  $(id).addEventListener("click", e => { const b = e.target.closest("button[data-k]"); if (!b) return; plan[key] = b.dataset.k; if (key === "style"){ try { localStorage.setItem("bi-style", plan.style); } catch(_){} } renderPlan(); });
$("spiceShelf").addEventListener("change", e => { spiceShelf = e.target.value.trim().slice(0, 600); try { localStorage.setItem("bi-spices", spiceShelf); } catch(_){} saveSettings().catch(()=>{}); });
$("pinChips").addEventListener("click", e => { const k = e.target.dataset?.unpin; if (k){ pins.delete(k); renderPlan(); renderPantry(); } });

function recipePrompt(pantry, portions){
  const d = DAYS.find(x=>x.k===plan.day), m = MEALS.find(x=>x.k===plan.meal);
  const kids = plan.who === "family" && ((household.c13||0)+(household.c46||0)+(household.c710||0)) > 0;
  const baby = plan.who === "family" && (household.baby||0) > 0;
  const lines = pantry.filter(p => !p.noNut).slice(0, 70).map(p => `${p.id} | ${p.name}${p.bio?" (organic)":""} | ${p.unknown && !p.left ? "amount unknown" : Math.round(p.left)+" g"} | ${p.dl <= 2 ? "USE SOON" : p.dl+" days left"}${pins.has(p.key) ? " | MUST INCLUDE" : ""} | ${Math.round(p.per.kcal||0)} kcal, ${(p.per.p||0).toFixed(1)} g protein, ${(p.per.c||0).toFixed(1)} g carbs, ${(p.per.f||0).toFixed(1)} g fat, ${(p.per.fib||0).toFixed(1)} g fibre`);
  const missingPins = [...pins].filter(k => !pantry.some(p=>p.key===k)).map(k=>k.split("|")[0]);
  return `You plan home-cooked meals for a household in Germany, from groceries they already bought.
Day: ${d.n}. ${d.note}
Meal: ${m.n}. Eating: ${whoText(plan.who)}. Make ${portions} adult-sized portions in total${kids ? " (young children eat less than an adult portion, by age)" : ""}.
Time: ${plan.time === "any" ? "no limit" : "at most " + plan.time + " minutes in total"}.
${trains() && plan.who !== "me" && ["pre","strength","z2","wp","game"].includes(plan.day) ? `Only one adult trains (about ${athlete.kg} kg); the day's targets apply to that person. Make the dish for everyone and give the athlete a bigger portion or an extra protein side (skyr, eggs, tofu, fish) so they get about ${plan.day === "pre" || plan.day === "game" ? "plenty of easy carbohydrate and 20–30 g protein" : "30–40 g protein with carbohydrate"}.\n` : ""}${kids ? "For young children: mild (no hot chilli), little added salt, whole nuts chopped or ground (choking risk under 5), round foods like cherry tomatoes cut in quarters. Add a one-line serving tip for the children.\n" : ""}${baby ? "The baby is breast- or bottle-fed and doesn't eat this.\n" : ""}
Ingredients in the kitchen (id | name | grams available | freshness | per 100 g):
${lines.join("\n")}
${missingPins.length ? `\nThey would also like to use: ${missingPins.join(", ")} (not in the kitchen; list under "buy").\n` : ""}
Rules: use mostly these ingredients; use ingredients marked USE SOON where they fit; ingredients marked MUST INCLUDE are required. Never use more grams than available. Basics you can assume: salt, black pepper, olive oil, rapeseed oil, vinegar, mustard, stock cube, garlic, onions, flour, sugar, soy sauce${spiceShelf ? ". Their spice shelf has exactly: " + spiceShelf + ". Spices not on this list (for example ground cumin, oregano, sumac) count as items to buy" : ", cumin, paprika, chilli flakes, dried oregano"}. Anything else goes under "buy": at most ${plan.style === "gourmet" ? "3 items per recipe; prefer fresh herbs, a lemon or long-lasting flavour builders (tahini, sumac, za'atar, preserved lemon, pomegranate molasses) that will serve many future meals" : "2 cheap, common items per recipe"}. Make three clearly different recipes that suit the day and the meal.
${plan.style === "italian" ? `Style: Italian home cooking in the style of GialloZafferano, but original recipes (don't reproduce their published recipes or name the site in the titles). Think like an Italian nonna and a careful recipe writer: regional classics and their honest variations (primi of pasta, risotto, gnocchi or soup; secondi; contorni; frittate; focaccia or pizza at the weekend), few good ingredients, correct technique (soffritto of onion, carrot and celery; salting pasta water; cooking pasta al dente and finishing it in the pan with starchy cooking water — mantecatura; toasting rice before adding hot stock; never cream in carbonara). Use Italian dish names with a short English gloss in the title, e.g. "Pasta e ceci (pasta with chickpeas)". Give precise steps with times and visual cues, and a tip on the key moment.${kids ? " Keep chilli out of the child's portion." : ""}` : plan.style === "gourmet" ? `Style: modern Middle Eastern and Mediterranean home cooking in the spirit of Yotam Ottolenghi, but original recipes (don't reproduce or name his published dishes). Build every dish in layers: a well-seasoned base, generous fresh herbs, acidity (lemon, sumac, pickled onion, yogurt), contrasting textures (crisp, creamy, crunchy), and a finishing flourish (dressing, toasted nuts or seeds, pomegranate, chilli butter or oil, a herb salsa). Vegetables are the stars; roast hard for colour. Give dishes evocative but plain titles. Keep the cooking achievable at home within the time limit.${kids ? " Keep heat and strong flavours in a topping or sauce served on the side, so the child's portion stays mild." : ""}` : plan.style === "kids" ? "Style: food children love (pasta, bakes, pancakes, dips, little bites), with a sharper topping or salad for the adults on the side." : "Style: simple, familiar home cooking with few steps."}
${LONG_PROMPT}
For each recipe also give "flavour" (a few words on its flavour profile) and "finish" (the last-minute touch that makes it).
Reply with only JSON:
{"recipes":[{"title":"","summary":"one sentence","why":"one sentence on why it suits this day","minutes":20,"ingredients":[{"id":"p3","g":200},{"basic":"olive oil","g":10,"n":{"kcal":884,"p":0,"c":0,"f":100,"fib":0,"sf":14,"s":0,"salt":0},"eurKg":9},{"buy":"red onion","g":150,"n":{"kcal":40,"p":1.1,"c":9,"f":0.1,"fib":1.7,"sf":0,"s":4.2,"salt":0},"eurKg":2.5}],"steps":["",""],"flavour":"","finish":"","kid":""}]}
"g" is grams for all ${portions} portions together. "n" holds typical values per 100 g and "eurKg" a typical German supermarket price, only for basics and bought items.`;
}
$("suggestBtn").onclick = async () => {
  if (!sample) return;
  const pantry = buildPantry(Math.max(pantryWin, 14));
  if (!pantry.length){ $("suggestStatus").textContent = "Nothing in the kitchen yet. Add a receipt first."; return; }
  const portions = portionsFor(plan.who);
  recCtl = new AbortController();
  $("suggestBtn").disabled = true; $("suggestStop").hidden = false; $("suggestStatus").className = "status";
  $("suggestStatus").textContent = "Putting recipes together from your kitchen… about 30–60 seconds.";
  try {
    const out = await sample.json(recipePrompt(pantry, portions), {signal: recCtl.signal});
    const recs = (out?.recipes || []).filter(r => r && r.title && Array.isArray(r.ingredients)).slice(0, 3);
    if (!recs.length) throw {code:"empty"};
    // freeze the pantry snapshot used, so costs and "cooked" deductions refer to the same lines
    recState = {plan: {...plan, spices: spiceShelf}, portions, at: new Date().toISOString(), recipes: recs, pantry: pantry.map(p => ({id:p.id, key:p.key, name:p.name, bio:p.bio, left:p.left, unknown:p.unknown, ppg:p.ppg, per:p.per, mic:p.mic, wg:p.wg, dl:p.dl, lines:p.lines}))};
    try { localStorage.setItem("bi-recipes", JSON.stringify(recState)); } catch(_){}
    $("suggestStatus").textContent = "";
    renderRecipes(); $("recResults").scrollIntoView({behavior:"smooth", block:"start"});
  } catch(e){
    $("suggestStatus").className = "status err";
    $("suggestStatus").textContent = e?.code === "cancelled" ? "Stopped." : e?.code === "not_granted" ? "Suggestions need your permission to use Claude on this page." : e?.code === "rate_limited" ? "Too many requests just now. Try again in a minute." : "The suggestions didn't come through. Try again.";
    if (e?.code === "cancelled") $("suggestStatus").className = "status";
  } finally { $("suggestBtn").disabled = !sample; $("suggestStop").hidden = true; }
};
$("suggestStop").onclick = () => recCtl?.abort();

function recipeMetrics(rec, st){
  const pm = Object.fromEntries(st.pantry.map(p => [p.id, p]));
  const tot = Object.fromEntries(NUT.map(n => [n.k, 0])), mic = {}; let cost = 0, grams = 0; const ings = [], issues = [];
  for (const ing of rec.ingredients || []){
    let g = Math.max(0, Number(ing.g) || 0);
    if (ing.id && pm[ing.id]){
      const P = pm[ing.id];
      if (P.left && g > P.left*1.05){ issues.push(`${P.name}: only about ${fmtGrams(P.left)} left, so the recipe is counted with that`); g = P.left; }
      for (const n of NUT){ if (n.calc) continue; tot[n.k] += (P.per[n.k]||0)*g/100; }
      for (const m of MIC) mic[m.k] = (mic[m.k]||0) + (P.mic[m.k]||0)*g/100;
      if (P.wg != null){ tot.grainK += (P.per.kcal||0)*g/100; tot.wgK += (P.per.kcal||0)*g/100*P.wg/100; }
      const c = P.ppg != null ? P.ppg*g : 0; cost += c; grams += g;
      ings.push({src:"kitchen", name:P.name, bio:P.bio, g, cost:c, P, soon: P.dl <= 2});
    } else {
      const n = ing.n || {};
      for (const k of ["kcal","p","c","f","fib","sf","s","salt"]) tot[k] += Math.max(0, Number(n[k])||0)*g/100;
      tot.co2 += co2Per100({name: String(ing.buy || ing.basic || ""), cat:"other"})*g/100;
      const c = Math.max(0, Number(ing.eurKg)||0)*g/1000; cost += c; grams += g;
      ings.push({src: ing.buy ? "buy" : "basic", name: String(ing.buy || ing.basic || "ingredient"), g, cost:c});
    }
  }
  const P = st.portions, nrf = nrfOf({...tot, mic, kg: grams/1000});
  return {tot, cost, perCost: cost/P, per: k => tot[k]/P, nrf, ings, issues};
}
function fitChecks(m, st){
  const d = DAYS.find(x=>x.k===st.plan.day), mf = (MEALS.find(x=>x.k===st.plan.meal)||{f:1}).f, out = [];
  const lab = {kcal:"energy", p:"protein", c:"carbs", f:"fat", fib:"fibre"}, unit = k => k==="kcal" ? " kcal" : " g";
  for (const [k,[lo,hi]] of Object.entries(d.t)){
    const v = m.per(k), L = lo != null ? lo*mf : null, H = hi != null ? hi*mf : null;
    const ok = (L == null || v >= L*0.9) && (H == null || v <= H*1.1);
    out.push(`<span class="${ok?"ok":"no"}">${ok?"✓":"!"} ${lab[k]} ${Math.round(v)}${unit(k)} <span class="status">(${L!=null&&H!=null?`${Math.round(L)}–${Math.round(H)}`:L!=null?`≥ ${Math.round(L)}`:`≤ ${Math.round(H)}`})</span></span>`);
  }
  return out.join("");
}
function renderRecipes(){
  const sec = $("recResults");
  if (!recState){ sec.hidden = true; return; }
  sec.hidden = false;
  const st = recState, d = DAYS.find(x=>x.k===st.plan.day), m = MEALS.find(x=>x.k===st.plan.meal);
  const ms = st.recipes.map(r => recipeMetrics(r, st));
  $("recMeta").textContent = `${d.n} · ${m.n} · ${st.portions} adult portion${st.portions===1?"":"s"} · ${new Date(st.at).toLocaleString("de-DE",{weekday:"short", hour:"2-digit", minute:"2-digit"})}`;
  // comparison chart
  const rows = [
    {n:"Cost per adult portion", f: x => x.perCost, fmt: v => eur(v), better:"low"},
    {n:"Energy per adult portion", f: x => x.per("kcal"), fmt: v => fmtInt(v)+" kcal"},
    {n:"Protein", f: x => x.per("p"), fmt: v => Math.round(v)+" g", better:"high"},
    {n:"Fibre", f: x => x.per("fib"), fmt: v => v.toLocaleString("de-DE",{maximumFractionDigits:1})+" g", better:"high"},
    {n:"Nutrient score", f: x => x.nrf || 0, fmt: v => Math.round(v), better:"high"},
    {n:"CO₂e per adult portion", f: x => x.per("co2"), fmt: v => fmtInt(v)+" g", better:"low"},
    {n:"From your kitchen", f: x => { const k = x.ings.filter(i=>i.src==="kitchen").reduce((a,i)=>a+i.g,0), all = x.ings.reduce((a,i)=>a+i.g,0); return all ? k/all*100 : 0; }, fmt: v => Math.round(v)+" %", better:"high"},
  ];
  $("recCompare").innerHTML = `<div class="row" style="justify-content:space-between;margin-bottom:10px"><h3>Side by side</h3>
      <div class="legend" style="margin:0">${st.recipes.map((r,i)=>`<span><i class="sw" style="background:${REC_COLORS[i]}"></i>${esc(r.title.length>28?r.title.slice(0,27)+"…":r.title)}</span>`).join("")}</div></div>
    <div class="cmpbars">${rows.map(row => { const vals = ms.map(row.f), mx = Math.max(...vals.map(Math.abs), 1e-9);
      const best = row.better ? vals.indexOf(row.better==="low" ? Math.min(...vals) : Math.max(...vals)) : -1;
      return `<div class="cb"><div>${esc(row.n)}</div><div class="bs">${vals.map((v,i)=>`<div class="b"><i style="width:${Math.max(1, Math.abs(v)/mx*100).toFixed(1)}%;background:${REC_COLORS[i]}"></i><span${i===best?' style="color:var(--fg);font-weight:600"':""}>${row.fmt(v)}</span></div>`).join("")}</div></div>`; }).join("")}</div>
    <p class="note" style="margin-top:8px">Costs use the prices on your receipts for what's in your kitchen, and typical supermarket prices for basics and anything to buy. Nutrition per adult portion; a child's portion is about two-thirds. Bold marks the best of the three.</p>`;
  $("recCards").innerHTML = st.recipes.map((r,i) => { const x = ms[i];
    const soon = x.ings.filter(g=>g.soon).map(g=>g.name);
    const buy = x.ings.filter(g=>g.src==="buy");
    return `<article class="rec" style="--rc:${REC_COLORS[i]}">
      <div><h3>${esc(r.title)}</h3><div class="meta">${Math.round(Number(r.minutes)||0) ? Math.round(r.minutes)+" min · " : ""}${eur(x.cost)} in total · ${eur(x.perCost)} per adult portion</div></div>
      ${r.summary ? `<p class="why" style="margin:0">${esc(r.summary)}</p>` : ""}
      ${r.flavour ? `<div class="chips">${String(r.flavour).split(/,|·|;/).map(t=>t.trim()).filter(Boolean).slice(0,4).map(t=>`<span class="chip fb">${esc(t)}</span>`).join("")}</div>` : ""}
      ${r.why ? `<p class="note" style="margin:0">${esc(r.why)}</p>` : ""}
      ${soon.length ? `<div class="chips">${soon.map(s=>`<span class="due now">uses ${esc(s)}</span>`).join("")}</div>` : ""}
      <div class="kpis"><div><b class="num">${fmtInt(x.per("kcal"))}</b>kcal</div><div><b class="num">${Math.round(x.per("p"))} g</b>protein</div><div><b class="num">${x.per("fib").toLocaleString("de-DE",{maximumFractionDigits:1})} g</b>fibre</div><div><b class="num">${Math.round(x.nrf||0)}</b>nutrient score</div><div><b class="num">${x.per("co2") >= 1000 ? (x.per("co2")/1000).toLocaleString("de-DE",{maximumFractionDigits:1})+" kg" : fmtInt(x.per("co2"))+" g"}</b>CO₂e</div></div>
      ${Object.keys(d.t).length ? `<div class="fit">${fitChecks(x, st)}</div>` : ""}
      <ul>${x.ings.map(g=>`<li>${fmtGrams(g.g)} ${esc(g.name)}${g.bio?" (organic)":""} <span class="src">· ${g.src==="kitchen"?"from your kitchen":g.src==="buy"?"to buy":"basic"}${g.cost>0.005?" · "+eur(g.cost):""}</span></li>`).join("")}</ul>
      ${x.issues.length ? `<p class="note" style="margin:0;color:var(--up)">${esc(x.issues.join(". "))}.</p>` : ""}
      <details><summary class="status" style="font-weight:600">Method (${(r.steps||[]).length} steps)</summary><ol style="margin-top:6px">${(r.steps||[]).map(s=>`<li>${esc(s)}</li>`).join("")}</ol></details>
      ${r.finish ? `<p class="note" style="margin:0"><b>To finish:</b> ${esc(r.finish)}</p>` : ""}
      ${r.kid ? `<p class="note" style="margin:0"><b>For the little one:</b> ${esc(r.kid)}</p>` : ""}
      <div class="acts"><button type="button" class="primary" data-cook="${i}" id="cook-${i}">We cooked this</button>${buy.length ? `<button type="button" data-shop="${i}" id="shop-${i}">Copy shopping list</button>` : ""}</div>
      <p class="status" id="cookStatus-${i}"></p>
    </article>`; }).join("");
}
$("recCards").addEventListener("click", async e => {
  const si = e.target.dataset?.shop;
  if (si != null){ const x = recipeMetrics(recState.recipes[+si], recState); const txt = x.ings.filter(g=>g.src==="buy").map(g=>`${g.name} (${fmtGrams(g.g)})`).join("\n");
    try { await navigator.clipboard.writeText(txt); $("cookStatus-"+si).textContent = "Shopping list copied."; } catch(_){ $("cookStatus-"+si).textContent = "To buy: " + txt.replace(/\n/g, ", "); } return; }
  const ci = e.target.dataset?.cook; if (ci == null) return;
  const b = e.target;
  if (b.dataset.armed !== "1"){ b.dataset.armed = "1"; b.textContent = "Confirm: log it and use the ingredients"; $("cookStatus-"+ci).textContent = "This takes the amounts out of your kitchen."; setTimeout(()=>{ if (b.isConnected && b.dataset.armed){ b.dataset.armed = ""; b.textContent = "We cooked this"; $("cookStatus-"+ci).textContent = ""; } }, 6000); return; }
  b.disabled = true;
  const st = recState, r = st.recipes[+ci], x = recipeMetrics(r, st);
  const usedG = usedByMeals();
  const uses = x.ings.filter(g=>g.src==="kitchen").map(g => {
    let need = g.g; const lines = [];
    for (const l of g.P.lines){                      // earliest-expiring first
      if (need <= 0) break;
      if (l.g == null){ lines.push({ref:l.ref, g:need}); need = 0; break; }
      const avail = Math.max(0, l.g - (usedG[l.ref]||0)); const take = Math.min(avail, need);
      if (take > 0){ lines.push({ref:l.ref, g:Math.round(take)}); need -= take; }
    }
    return {key:g.P.key, name:g.name, g:Math.round(g.g), lines};
  });
  const meal = {kind:"meal", id:"meal-"+Date.now().toString(36), date: todayISO(), day: st.plan.day, meal: st.plan.meal, who: st.plan.who, title: r.title, portions: st.portions,
    perAdult: {kcal: x.per("kcal"), p: x.per("p"), c: x.per("c"), f: x.per("f"), fib: x.per("fib"), sf: x.per("sf"), s: x.per("s"), salt: x.per("salt"), co2: x.per("co2")}, cost: x.cost, perCost: x.perCost, nrf: x.nrf,
    uses, recipe: {title:r.title, summary:r.summary||"", flavour:r.flavour||"", finish:r.finish||"", ingredients: x.ings.map(g=>({name:g.name, g:Math.round(g.g), src:g.src})), steps: r.steps||[], kid: r.kid||""}, savedAt: new Date().toISOString()};
  try {
    if (db && uid) await db.collection(COL).doc(meal.id).set(meal); else { meals.push(meal); renderAll(); }
    $("cookStatus-"+ci).textContent = "Logged. The ingredients are out of your kitchen."; b.textContent = "Logged";
  } catch(_){ b.disabled = false; b.dataset.armed = ""; b.textContent = "We cooked this"; $("cookStatus-"+ci).textContent = "Couldn't log it just now. Try again."; }
});
