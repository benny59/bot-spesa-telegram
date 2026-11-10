"use strict";
// =====================================================================
// Week planner: the cheapest week of shopping that meets your household's nutrient targets,
// uses up what's about to go off, and stays close to what you like to buy (a linear programme).
// =====================================================================
const WD = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
const SLOTS = [{k:"b", n:"Breakfast", sh:.25, meal:"breakfast"}, {k:"l", n:"Lunch", sh:.35, meal:"lunch"}, {k:"d", n:"Dinner", sh:.30, meal:"dinner"}];
const SNACK_SHARE = .10;
// ---------- Training: one adult's sessions, through the week ----------
// MET values from the Compendium of Physical Activities (net of rest: MET − 1); carbohydrate and protein per kg body weight
// from the sports-nutrition consensus (IOC 2011, ACSM/AND/DC 2016, ISSN 2017).
const SESS = {
  strength: {n:"Strength",          met:5,   min:60, cg:4.5, pg:1.6},
  z2:       {n:"Zone 2 cardio",     met:6.5, min:50, cg:5,   pg:1.4},
  yoga:     {n:"Yoga & mobility",   met:2.5, min:45, cg:3.5, pg:1.2},
  wp:       {n:"Water polo training", met:10, min:90, cg:6.5, pg:1.6},
  game:     {n:"Water polo game",   met:10,  min:75, cg:7,   pg:1.6},
  cardio:   {n:"Other cardio",      met:7,   min:45, cg:5,   pg:1.4},
};
const WHEN = {early:"Before breakfast", morning:"Morning, after breakfast", midday:"Around midday", afternoon:"Afternoon", evening:"Evening, before dinner"};
// Protein: 1.6 g/kg is where extra protein stops adding muscle with resistance training (Morton 2018);
// 1.2 g/kg on easy days keeps muscle in midlife without the high intakes some cohorts link to higher risk.
const REST_CG = 3.5, REST_PG = 1.2;
let athlete = {kg: 75};
const DEFAULT_SESS = [[],[],[],[],[],[],[]];   // nobody trains until it is entered
let week = WD.map((_, i) => ({t: i >= 5 ? "weekend" : "busy", b:1, l: i >= 5 ? 1 : 0, d:1, s: DEFAULT_SESS[i]}));
function trains(){ return (household.adult||0) >= 1 && athlete.kg > 0; }
// What the training adds for that adult on one weekday, above an ordinary adult's reference.
function trainExtra(wi){
  const out = {kcal:0, p:0, c:0}; if (!trains()) return out;
  const ss = week[wi]?.s || [], kg = athlete.kg;
  for (const x of ss){ const S = SESS[x.k]; if (S) out.kcal += (S.met - 1)*kg*(Number(x.min)||S.min)/60; }
  const cg = Math.max(REST_CG, ...ss.map(x => SESS[x.k]?.cg || 0)), pg = Math.max(REST_PG, ...ss.map(x => SESS[x.k]?.pg || 0));
  out.p = Math.max(0, pg*kg - ADULT_DAY.p);
  out.c = Math.max(0, cg*kg - ADULT_DAY.c, out.kcal*0.55/4);
  return out;
}
function trainAvg(k){ let t = 0; for (let i = 0; i < 7; i++) t += trainExtra(i)[k] || 0; return t/7; }
function sessText(x){ const S = SESS[x.k]; return `${S ? S.n : x.k}, ${(WHEN[x.when]||"").toLowerCase()}, ${Number(x.min)||S?.min||0} min${x.note ? " (" + x.note + ")" : ""}`; }
// What each meal is for, given the day's sessions (for the athlete; everyone else just eats well).
function mealRoles(wi, ssIn){
  const ss = ssIn || week[wi]?.s || [], r = {};
  const hard = x => ["wp","game","z2","cardio"].includes(x.k), name = x => SESS[x.k]?.n.toLowerCase() || "training";
  for (const x of ss){
    if (x.k === "yoga"){ r.note = (r.note ? r.note + " " : "") + "Yoga needs no special fuelling; keep the meal before it light."; continue; }
    if (x.when === "early"){ r.breakfast = `recovery after ${name(x)} before breakfast: the athlete needs 30–40 g protein with carbohydrate`; if (hard(x)) r.pre = "a banana or small snack before the session if it's long or hard"; }
    if (x.when === "morning"){ r.breakfast = `1–2 hours before ${name(x)}: carbohydrate-forward, light on fat and fibre`; r.lunch = `recovery after ${name(x)}: 30–40 g protein for the athlete, plus carbohydrate`; }
    if (x.when === "midday"){ r.snack = `easy carbohydrate 1–2 hours before ${name(x)}`; r.lunch = `recovery after ${name(x)}`; }
    if (x.when === "afternoon"){ r.lunch = `the main pre-${name(x)} meal, 3–4 hours before: carbohydrate-rich, moderate protein, low in fat and fibre, familiar food`; r.snack = `1–2 hours before ${name(x)}: easily digested carbohydrate (banana, bread with honey, rice cakes)`; r.dinner = `recovery after ${name(x)}: 30–40 g protein for the athlete, carbohydrate to refill, salty fluids`; }
    if (x.when === "evening"){ r.snack = `pre-${name(x)} fuel in the late afternoon: carbohydrate and a little protein`; r.dinner = `a late recovery dinner after ${name(x)}: 30–40 g protein and carbohydrate for the athlete, easy to digest so it doesn't spoil sleep`; }
  }
  if (!ss.length) r.note = "Rest day for the athlete: a little less energy, plenty of vegetables, fibre and omega-3.";
  return r;
}
function rolesText(wi, ss){ const r = mealRoles(wi, ss); return [r.pre && "before: " + r.pre, r.breakfast && "breakfast = " + r.breakfast, r.lunch && "lunch = " + r.lunch, r.snack && "snack = " + r.snack, r.dinner && "dinner = " + r.dinner, r.note].filter(Boolean).join("; "); }
// Suggest today's kind of day and meal for one-off recipes, from the training week.
function suggestToday(){
  const now = new Date(), wi = (now.getDay()+6)%7, h = now.getHours(), ss = week[wi]?.s || [];
  const meal = h < 10 ? "breakfast" : h < 15 ? "lunch" : h < 17 ? "snack" : "dinner";
  const kindOf = x => x.k === "strength" ? "strength" : x.k === "z2" || x.k === "cardio" ? "z2" : x.k === "yoga" ? "yoga" : x.k === "game" ? "game" : "wp";
  let day = (wi >= 5) ? "weekend" : "busy";
  if (!ss.length && wi === 6) day = "yoga";
  for (const x of ss){
    const before = (x.when === "afternoon" && (meal === "lunch" || meal === "snack")) || (x.when === "evening" && meal === "snack") || (x.when === "morning" && meal === "breakfast") || (x.when === "midday" && meal === "breakfast");
    const after = (x.when === "early" && meal === "breakfast") || (x.when === "morning" && meal === "lunch") || (x.when === "midday" && meal === "lunch") || ((x.when === "afternoon" || x.when === "evening") && meal === "dinner");
    if (before) day = x.k === "game" ? "game" : x.k === "yoga" ? day : "pre";
    else if (after) day = kindOf(x);
  }
  return {day, meal, wi, ss};
}
let planOpts = {climate:"20", change:"balanced", start:"tomorrow"};
let weekPlan = null, wpBusy = false, wpCtl = null, recTab = "week";
try { const t = localStorage.getItem("bi-rectab"); if (["week","meal","kitchen","cooked"].includes(t)) recTab = t; } catch(_){}
function planStart(){
  const t = todayISO();
  if (planOpts.start === "today") return t;
  if (planOpts.start === "monday"){ const wd = (d2(t).getUTCDay()+6)%7; return addDays(t, 7 - wd); }
  return addDays(t, 1);
}
function planDays(start){ return Array.from({length:7}, (_, i) => { const ds = addDays(start, i), wi = (d2(ds).getUTCDay()+6)%7; return {ds, wi, ...week[wi]}; }); }
function dayCov(w){ return SNACK_SHARE + SLOTS.reduce((a,s) => a + (w[s.k] ? s.sh : 0), 0); }
const PLAN_DROP = new Set(["spices","coffee","tea","water","cocoa"]);
const PLAN_KEYS = ["kcal","p","c","f","sf","s","salt","fib","n3","mufa","pufa","grainK","wgK","co2"];
const PLAN_MIC = ["vc","va","vd","b12","fol","ca","fe","mg","k","zn"];
// Products you've bought in the last 90 days: nutrition per kg edible, the cheapest shop for each, pack sizes and how much you usually buy.
function buildCandidates(){
  const today = todayISO(), C = {};
  const list = cleanReceipts().filter(r => { const a = days(r.date, today); return a >= 0 && a <= 90; });
  if (!list.length) return {cands: [], weeks: 1};
  const first = list.reduce((a,r)=>a<r.date?a:r.date, today), weeks = Math.max(1, (days(first, today)+1)/7);
  for (const r of [...list].sort((a,b)=>a.date.localeCompare(b.date))) for (const it of r.items){
    if (!isFood(it) || isSlip(it) || !(it.price > 0)) continue;
    const ct = co2Type(it); if (PLAN_DROP.has(ct)) continue;
    const ln = lineNutrition(it); if (!ln || !(ln.kg > 0)) continue;
    const key = (it.g || it.name).toLowerCase().trim() + (it.bio ? "|bio" : "");
    const P = (C[key] ||= {key, name: it.g || it.name, bio: !!it.bio, cat: it.cat, ct, kg: 0, n: 0, sum: {}, mic: {}, stores: {}, ns: nsOf(it)?.grade || ""});
    P.kg += ln.kg; P.n++;
    for (const k of PLAN_KEYS) P.sum[k] = (P.sum[k]||0) + (ln[k]||0);
    if (ln.mic) for (const k of PLAN_MIC) P.mic[k] = (P.mic[k]||0) + (ln.mic[k]||0);
    const per = it.unit === "kg" ? {kg: ln.kg/(it.qty||1), price: unitPriceOf(it), weighed: true} : {kg: ln.kg/(it.qty||1), price: it.price/(it.qty||1), size: it.size||""};
    P.stores[chainLabel(r.store)] = {...per, ppk: per.price/per.kg, date: r.date, name: it.name};
  }
  const cands = Object.values(C).map(P => {
    const a = {}; for (const k of PLAN_KEYS) a[k] = P.sum[k]/P.kg;          // per kg edible
    const m = {}; for (const k of PLAN_MIC) m[k] = P.mic[k]/P.kg;
    const best = Object.entries(P.stores).sort((x,y)=>x[1].ppk-y[1].ppk)[0];
    return {...P, a, m, wg: a.grainK > 0 ? a.wgK/a.grainK*100 : null, store: best[0], pack: best[1], ppk: best[1].ppk, habit: P.kg/weeks};
  }).filter(P => P.a.kcal > 0 && isFinite(P.ppk));
  return {cands, weeks};
}
const isVeg = x => x.cat === "veg" && x.ct !== "potatoes";
const isFruit = x => x.cat === "fruit" && !["nuts","seeds","dried","freezedried"].includes(x.ct);
// The model. Variables: kg (edible) of each product to buy, kg of each kitchen item to use, then one slack per soft target.
function buildModel(opt){
  const {cands, pantry, covSum, adultEq, changeF, onlyHabit, climateR, horizon, pd} = opt;
  // Targets day by day: household reference plus what that day's training adds, times the share eaten at home.
  const T = k => !(k in ADULT_DAY) ? 0 : pd ? pd.reduce((a,w) => a + (ADULT_DAY[k]*famFactor(k) + (trainExtra(w.wi)[k]||0))*dayCov(w), 0) : famDay(k)*covSum;
  const vars = [];
  // What you usually buy already reflects the meals you eat at home, so it is taken as it is.
  const covF = 1;
  for (const P of cands){
    const hs = P.habit*covF, packKg = P.pack.weighed ? 0.25 : P.pack.kg;
    if (onlyHabit && P.n < 2) continue;
    const good = LONG.some(L => L.min && L.f(P) > 0);
    let cap = Math.max(changeF*hs, packKg*(good ? Math.round(changeF) : 1));
    if (P.a.kcal > 0) cap = Math.min(cap, 0.15*T("kcal")/P.a.kcal);
    vars.push({type:"buy", P, cost: P.ppk, cap, hs, a: P.a, m: P.m});
  }
  for (const Q of pantry){
    const left = Q.left/1000, val = Q.ppg != null ? Q.ppg*1000 : 4;
    const soon = Q.dl <= horizon;
    vars.push({type:"kitchen", Q, cost: soon ? -1.2*val : 0.5*val, cap: left, soon, hs: 0, a: Object.fromEntries(PLAN_KEYS.map(k => [k, k === "grainK" ? (Q.wg != null ? (Q.per.kcal||0)*10 : 0) : k === "wgK" ? (Q.wg != null ? (Q.per.kcal||0)*10*Q.wg/100 : 0) : (Q.per[k]||0)*10])), m: Object.fromEntries(PLAN_MIC.map(k => [k, (Q.mic[k]||0)*10])), cat: Q.cat, ct: Q.ct, name: Q.name, wg: Q.wg});
  }
  const n0 = vars.length;
  const habitCost = vars.reduce((s,v) => s + (v.type === "buy" ? v.hs*v.cost : 0), 0);
  const B = Math.max(40, habitCost);
  const rows = [], soft = [];
  const add = (coef, op, b, w, label) => { soft.push({op, w: w*B/20, label}); rows.push({coef, op, b, slack: soft.length-1}); };
  const lin = f => vars.map(f);
  const nut = k => lin(v => (v.a[k]||0)/T(k));
  const micr = k => lin(v => (v.m[k]||0)/T(k));
  add(nut("kcal"), ">=", 0.97, 60, "Energy"); add(nut("kcal"), "<=", 1.05, 60, "Energy (max)");
  add(nut("p"), ">=", 1, 40, "Protein"); add(nut("fib"), ">=", 1, 25, "Fibre"); add(nut("c"), ">=", 0.9, 10, "Carbohydrate");
  add(nut("n3"), ">=", 1, 15, "Omega-3"); add(nut("f"), ">=", 0.7, 8, "Fat"); add(nut("f"), "<=", 1.2, 10, "Fat (max)");
  add(nut("sf"), "<=", 1, 30, "Saturated fat"); add(nut("s"), "<=", 1, 15, "Sugars"); add(nut("salt"), "<=", 1, 25, "Salt");
  for (const k of PLAN_MIC) add(micr(k), ">=", 1, k === "vd" ? 3 : 20, MIC.find(x=>x.k===k).n);
  const longT = {};
  for (const L of LONG){ const tgt = (L.min || L.max)/1000*adultEq*covSum; longT[L.k] = tgt; add(lin(v => L.f(v.P || v)/tgt), L.min ? ">=" : "<=", 1, L.w, L.n); }
  const vegT = longT.veg, fruT = longT.fruit;
  add(lin(v => (v.P || v).cat === "sweets" ? (v.a.kcal||0)/T("kcal") : 0), "<=", 0.05, 15, "Sweets");
  add(lin(v => (v.a.p||0)*(isPlantCt((v.P || v).ct) ? 0.5 : -0.5)/T("p")), ">=", 0, 12, "Plant protein");
  add(lin(v => ((v.a.wgK||0) - 0.5*(v.a.grainK||0))/T("kcal")), ">=", 0, 10, "Wholegrain");
  let co2Base = null;
  if (climateR > 0){
    const hk = cands.reduce((s,P)=>s+P.habit*P.a.kcal,0), hc = cands.reduce((s,P)=>s+P.habit*P.a.co2,0);
    co2Base = hk > 0 ? hc/hk*T("kcal") : null;
    if (co2Base) add(lin(v => (v.a.co2||0)/(co2Base*(1-climateR))), "<=", 1, 40, "Climate");
  }
  // assemble: columns = vars, then slacks
  const nS = soft.length, N = n0 + nS, c = new Array(N).fill(0), A = [];
  vars.forEach((v,j) => c[j] = v.cost);
  soft.forEach((s,i) => c[n0+i] = s.w);
  for (const r of rows){ const a = new Array(N).fill(0); r.coef.forEach((v,j) => a[j] = v); a[n0 + r.slack] = r.op === ">=" ? 1 : -1; A.push({a, op: r.op, b: r.b}); }
  vars.forEach((v,j) => { const a = new Array(N).fill(0); a[j] = 1; A.push({a, op:"<=", b: Math.max(0, v.cap)}); });
  return {vars, soft, c, rows: A, n0, B, T, vegT, fruT, longT, co2Base, habitCost};
}
function solveWeek(){
  const start = planStart(), pd = planDays(start), covSum = pd.reduce((a,w)=>a+dayCov(w),0);
  const {cands} = buildCandidates();
  const pantry = buildPantry(21).filter(Q => Q.left > 20 && Q.dl >= 0 && !Q.unknown && !Q.noNut && !PLAN_DROP.has(Q.ct));
  const changeF = {close:1.3, balanced:2, bold:3}[planOpts.change] || 2;
  const opt = {cands, pantry, covSum, pd, adultEq: famFactor("kcal"), changeF, onlyHabit: planOpts.change === "close", climateR: (+planOpts.climate||0)/100, horizon: 6};
  const M = buildModel(opt);
  if (!M.vars.length) return null;
  const t0 = performance.now(), sol = lpSolve(M.c, M.rows, 200000), ms = performance.now()-t0;
  if (sol.status !== "optimal") return {error: sol.status};
  // round to what you can buy: whole packs, or 100 g steps for weighed products
  const items = [];
  M.vars.forEach((v,j) => {
    const x = sol.x[j]; if (x < 0.005) return;
    if (v.type === "kitchen"){ const Q = v.Q; items.push({src:"kitchen", key:Q.key, name:Q.name, bio:Q.bio, cat:Q.cat, ct:Q.ct, wg:Q.wg, g: Math.round(Math.min(x, Q.left/1000)*1000), soon: v.soon, dl: Q.dl, a: v.a, m: v.m, ppk: (Q.ppg||0)*1000, cost: 0}); return; }
    const P = v.P; let packs, kg;
    if (P.pack.weighed){ kg = Math.max(0.1, Math.round(x/(P.pack.kg||1)*10)/10*(P.pack.kg||1)); packs = null; }
    else { packs = Math.round(x/P.pack.kg); if (packs === 0 && x/P.pack.kg >= 0.35) packs = 1; if (!packs) return; kg = packs*P.pack.kg; }
    items.push({src:"buy", key:P.key, name:P.name, bio:P.bio, cat:P.cat, ct:P.ct, wg:P.wg, ns:P.ns, g: Math.round(kg*1000), packs, size: P.pack.size||"", weighed: !!P.pack.weighed, store: P.store, rname: P.pack.name,
      cost: P.pack.weighed ? kg/(P.pack.kg||1)*P.pack.price : packs*P.pack.price, a: P.a, m: P.m, ppk: P.ppk, habit: v.hs, isNew: P.n < 2});
  });
  const tot = (arr, f) => { const t = {}; for (const k of [...PLAN_KEYS, ...PLAN_MIC]) t[k] = 0; for (const it of arr){ const kg = f(it); for (const k of PLAN_KEYS) t[k] += (it.a[k]||0)*kg; for (const k of PLAN_MIC) t[k] += (it.m[k]||0)*kg; } return t; };
  const planTot = tot(items, it => it.g/1000);
  const usual = M.vars.filter(v => v.type === "buy");
  const usualTot = tot(usual.map(v => ({a:v.a, m:v.m, hs:v.hs})), it => it.hs);
  const veg = items.filter(isVeg).reduce((a,i)=>a+i.g,0)/1000, fruit = items.filter(isFruit).reduce((a,i)=>a+i.g,0)/1000;
  const uVeg = usual.filter(v => isVeg(v.P)).reduce((a,v)=>a+v.hs,0), uFruit = usual.filter(v => isFruit(v.P)).reduce((a,v)=>a+v.hs,0);
  const longP = longGrams(items, it => it.g/1000), longU = longGrams(usual.map(v => ({...v.P, hs: v.hs})), it => it.hs);
  const plantP = items.reduce((a,it)=>a+(isPlantCt(it.ct) ? (it.a.p||0)*it.g/1000 : 0),0), plantU = usual.reduce((a,v)=>a+(isPlantCt(v.P.ct) ? (v.a.p||0)*v.hs : 0),0);
  const targets = Object.fromEntries([...PLAN_KEYS, ...PLAN_MIC].filter(k => k in ADULT_DAY).map(k => [k, M.T(k)]));
  return {kind:"weekplan", id:"weekplan", at: new Date().toISOString(), start, days: pd.map(w => ({ds:w.ds, wi:w.wi, t:w.t, b:w.b, l:w.l, d:w.d, s:w.s||[]})), opts: {...planOpts}, covSum, train: trains() ? {kg: athlete.kg, kcal: Math.round(pd.reduce((a,w)=>a+trainExtra(w.wi).kcal*dayCov(w),0))} : null,
    items: items.map(it => ({...it, a: roundObj(it.a), m: roundObj(it.m)})), tot: roundObj(planTot), usual: roundObj(usualTot), targets: roundObj(targets),
    veg, fruit, vegT: M.vegT, fruT: M.fruT, uVeg, uFruit, longP: roundObj(longP), longU: roundObj(longU), longT: roundObj(M.longT), plantShare: planTot.p > 0 ? plantP/planTot.p : 0, plantShareU: usualTot.p > 0 ? plantU/usualTot.p : 0, usualCost: M.habitCost, co2Base: M.co2Base, lp: {ms: Math.round(ms), iters: sol.iters, vars: M.vars.length, rows: M.rows.length}, menu: null};
}
function roundObj(o){ const r = {}; for (const k in o) r[k] = Math.round(o[k]*1000)/1000; return r; }
