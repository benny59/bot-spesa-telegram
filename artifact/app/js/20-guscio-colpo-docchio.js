"use strict";
let rzW = 0;
window.addEventListener("resize", () => { const w = $("chartBox").clientWidth; if (Math.abs(w-rzW) > 40){ rzW = w; renderTrack(); } });
// =====================================================================
// App shell: four views behind tabs, linked by #prices #nutrition #recipes #receipts
// =====================================================================
const VIEWS = ["prices","nutrition","recipes","receipts"];
let view = "prices";
let lastNut = null, lastSav = null;
function todayISO(){ const d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset()*6e4).toISOString().slice(0,10); }
function weekday(ds){ return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][d2(ds).getUTCDay()]; }
function showView(v, opts = {}){
  if (!VIEWS.includes(v)) v = "prices";
  view = v;
  for (const x of VIEWS){ const on = x === v; $("view-"+x).hidden = !on; const t = $("tab-"+x); t.setAttribute("aria-selected", on); t.tabIndex = on ? 0 : -1; }
  try { localStorage.setItem("bi-view", v); } catch(_){}
  try { if (location.hash !== "#"+v) history.replaceState(null, "", "#"+v); } catch(_){}
  if (opts.focus && $(opts.focus)){ const pnl = $(opts.focus).closest("[id^=rp-]"); if (pnl){ recTab = pnl.id.slice(3); try { localStorage.setItem("bi-rectab", recTab); } catch(_){} } }
  renderAll();
  if (opts.focus && $(opts.focus)) $(opts.focus).scrollIntoView({behavior:"smooth", block:"start"});
  else if (opts.scroll !== false) window.scrollTo({top:0});
}
document.querySelector(".tabs").addEventListener("click", e => { const b = e.target.closest("button[data-view]"); if (b) showView(b.dataset.view); });
document.querySelector(".tabs").addEventListener("keydown", e => {
  if (!["ArrowLeft","ArrowRight","Home","End"].includes(e.key)) return;
  e.preventDefault(); const i = VIEWS.indexOf(view);
  const n = e.key==="Home" ? VIEWS[0] : e.key==="End" ? VIEWS[VIEWS.length-1] : VIEWS[(i + (e.key==="ArrowRight" ? 1 : VIEWS.length-1)) % VIEWS.length];
  showView(n, {scroll:false}); $("tab-"+n).focus();
});
window.addEventListener("hashchange", () => { const h = location.hash.slice(1); if (VIEWS.includes(h) && h !== view) showView(h); });
$("addReceiptTop").onclick = () => { showView("receipts", {scroll:false}); $("photo").click(); };
document.addEventListener("click", e => { const g = e.target.closest("[data-go]"); if (!g) return; showView(g.dataset.go, {focus: g.dataset.focus}); });

// ---------- At a glance ----------
function tile(k, v, s, go, goTxt, focus){
  const inner = `<span class="k">${esc(k)}</span><span class="v num">${v}</span><span class="s">${s}</span>${go ? `<span class="go">${esc(goTxt)} →</span>` : ""}`;
  return go ? `<button type="button" class="gl" data-go="${go}"${focus ? ` data-focus="${focus}"` : ""}>${inner}</button>` : `<div class="gl">${inner}</div>`;
}
function renderGlance(){
  const today = todayISO(), clean = cleanReceipts();
  const pts = (() => { const keep = matchMode; matchMode = "same"; const sf = storeFilter; storeFilter = "all"; const r = chain(); matchMode = keep; storeFilter = sf; return r; })();
  const last7 = clean.filter(r => days(r.date, today) < 7 && days(r.date, today) >= 0);
  const sp7 = last7.reduce((a,r)=>a+r.items.filter(isFood).reduce((x,i)=>x+i.price,0),0);
  const first = clean.reduce((a,r)=>a<r.date?a:r.date, today);
  const weeksAll = Math.max(1, (days(first, today)+1)/7);
  const spAll = clean.reduce((a,r)=>a+r.items.filter(isFood).reduce((x,i)=>x+i.price,0),0);
  const idx = pts.length > 1 ? pct((pts[pts.length-1].I/100-1)*100) : "–";
  const pantry = buildPantry(7), soon = pantry.filter(p => p.dl <= 2);
  $("glance-prices").innerHTML =
    tile("Your price index", idx, pts.length > 1 ? `since ${fmtDay(pts[0].date)}, same products in the same shop` : "builds up as products repeat", null) +
    tile("Food, last 7 days", eur(sp7), `${eur(spAll/weeksAll)} a week on average`, "receipts", "See receipts") +
    tile("Best-price savings", lastSav && lastSav.tot > 0 ? eur(lastSav.tot) : "–", lastSav && lastSav.tot > 0 ? `had every repeat bought at its lowest price` : "appears once products repeat", "nutrition", "Value for money", "nutPrice");
  if (lastNut && lastNut.counted){
    const ns = lastNut.nsSpend, nsT = Object.values(ns).reduce((a,b)=>a+b,0);
    $("glance-nutrition").innerHTML =
      tile("Nutri-Score A or B", nsT ? Math.round((ns.A+ns.B)/nsT*100)+" %" : "–", "of food spending", null) +
      tile("Protein per euro", (lastNut.tot.p/lastNut.counted).toLocaleString("de-DE",{maximumFractionDigits:1})+" g", `fibre ${(lastNut.tot.fib/lastNut.counted).toLocaleString("de-DE",{maximumFractionDigits:1})} g per euro`, null) +
      tile("Use soon", String(soon.length), soon.length ? esc(soon.slice(0,3).map(p=>p.name).join(", ")) : "nothing urgent in the kitchen", "recipes", "Cook with them", "pantryCard");
  } else $("glance-nutrition").innerHTML = "";
  const wkMeals = meals.filter(m => days(m.date, today) < 7);
  const avgC = wkMeals.length ? wkMeals.reduce((a,m)=>a+(m.perCost||0),0)/wkMeals.length : null;
  const kcal7 = last7.reduce((a,r)=>a+r.items.reduce((x,i0)=>{ const ln = lineNutrition(withLib(r,i0)); return x + (ln ? ln.kcal : 0); },0),0);
  $("glance-recipes").innerHTML =
    tile("Use soon", String(soon.length), soon.length ? esc(soon.slice(0,3).map(p=>p.name).join(", ")) : "nothing urgent", null) +
    tile("Meals logged, 7 days", String(wkMeals.length), avgC != null ? `${eur(avgC)} per adult portion on average` : "log a meal with “We cooked this”", null) +
    tile("Bought, last 7 days", fmtInt(kcal7)+" kcal", famDay("kcal") > 0 ? `about ${(kcal7/famDay("kcal")).toLocaleString("de-DE",{maximumFractionDigits:1})} days of food for your household` : "", "nutrition", "Nutrition");
}
