"use strict";
// ---------- Boot ----------
function applySuggest(){ try { const sg = suggestToday(); plan.day = sg.day; plan.meal = sg.meal; } catch(_){} }
applySuggest();
if (location.protocol === "file:") window.__biDebug = {buildCandidates, buildModel, solveWeek, lpSolve, planDays, planStart, dayCov, buildPantry, famFactor, get planOpts(){ return planOpts; }};
try { const h = location.hash.slice(1); view = VIEWS.includes(h) ? h : (localStorage.getItem("bi-view") || "prices"); if (!VIEWS.includes(view)) view = "prices"; } catch(_){}
for (const x of VIEWS){ $("view-"+x).hidden = x !== view; $("tab-"+x).setAttribute("aria-selected", x === view); $("tab-"+x).tabIndex = x === view ? 0 : -1; }
try { storeFilter = localStorage.getItem("bi-store") || "all"; matchMode = localStorage.getItem("bi-mode") === "any" ? "any" : "same"; mergeOrganic = localStorage.getItem("bi-merge") === "1"; } catch(_){}
$("mergeBio").checked = mergeOrganic;
renderRates(); renderAll();
(async () => {
  if (!window.claude?.use){ loaded = true; renderAll(); return; }
  const [s, d, u] = await Promise.all([claude.use("sample"), claude.use("db"), claude.use("user")]);
  sample = s;
  if (sample){ const lim = await sample.limits().catch(()=>null); if (!lim?.images) sample = null; }
  if (!sample) $("aiStatus").textContent = "Reading photos is not available in this view.";
  if (u) uid = await u.id().catch(()=>null);
  // The household's data lives in one shared place for the owner and anyone they've made an Editor
  // (e.g. a partner); anyone else keeps their own private data.
  const ask = async f => { try { return !!(await f()); } catch(_){ return false; } };
  const shared = u ? ((await ask(() => u.isOwner())) || (await ask(() => u.canEdit()))) : false;
  if (uid) COL = shared ? "household" : "data/users/" + uid;
  if (!d){ loaded = true; renderAll(); return; }
  db = d;
  // Official monthly releases (shared, read-only for the page)
  db.collection("official").onSnapshot(snap => {
    const next = {[FALLBACK.month]: FALLBACK};
    for (const x of snap.docs){ const v = x.data(); if (v && v.month && v.de && v.ea) next[v.month] = v; }
    official = next; renderRates(); renderAll();
  }, () => {});
  if (!uid){ loaded = true; renderAll(); return; }
  db.collection(COL).onSnapshot(snap => {
    const docs = snap.docs.map(x=>x.data());
    tuttiDocs = snap.docs.map(x => ({id: x.id, data: x.data()}));
    receipts = docs.filter(x=>x?.kind==="receipt");
    library = {}; for (const pd of docs) if (pd?.kind==="product" && pd.key) library[pd.key] = pd;
    const fd = docs.find(x=>x?.kind==="favs"); favs = Array.isArray(fd?.favorites) ? fd.favorites : favs;
    if (typeof statoPreferiti === "function") statoPreferiti();
    memVer++;
    meals = docs.filter(x=>x?.kind==="meal");
    pantryDoc = docs.find(x=>x?.kind==="pantry") || {used:{}};
    const st = docs.find(x=>x?.kind==="settings");
    overrides = st?.overrides || null;
    if (st && typeof st.spices === "string" && st.spices && document.activeElement !== $("spiceShelf")) spiceShelf = st.spices;
    if (st?.household && typeof st.household === "object") household = {adult:0, c13:0, c46:0, c710:0, baby:0, ...st.household};
    else if (st && st.people > 0) household = {adult: st.people, c13:0, c46:0, c710:0, baby:0};
    if (Array.isArray(st?.week) && st.week.length === 7){ const hasS = st.week.some(w => Array.isArray(w?.s));
      week = st.week.map((w,i) => ({t: w?.t === "weekend" ? "weekend" : "busy", b: w?.b ? 1 : 0, l: w?.l ? 1 : 0, d: w?.d ? 1 : 0, s: hasS ? (Array.isArray(w?.s) ? w.s.filter(x => SESS[x?.k] && WHEN[x?.when]) : []) : DEFAULT_SESS[i]})); }
    if (st?.athlete?.kg >= 35 && st.athlete.kg <= 200) athlete = {...athlete, kg: st.athlete.kg};
    if (!window.__sgDone){ window.__sgDone = true; applySuggest(); }
    if (st?.planOpts && typeof st.planOpts === "object") planOpts = {...planOpts, ...st.planOpts};
    const wpd = docs.find(x=>x?.kind==="weekplan"); if (wpd && (!weekPlan || wpd.at >= weekPlan.at)) weekPlan = wpd;
    loaded = true;
    if (draftIsExample && receipts.some(r=>r.date===EXAMPLE.date)){ draft = null; draftIsExample = false; }
    renderRates(); renderAll();
  }, () => { loaded = true; renderAll(); });
})();
