"use strict";
// ---------- Your own chained price index ----------
// Article number plus the start of the name: some stores (HIT) print short codes that repeat across products.
function itemKey(store, it){
  const stem = String(it.name||"").toLowerCase().replace(/[^a-z0-9äöüß]+/g,"");
  return chainOf(store) + "|" + (it.code ? "c"+it.code+":"+stem.slice(0,4) : "n"+stem);
}
// The printed unit price where there is one (per-kg lines), else line total / quantity.
function unitPriceOf(it){ return it.unitPrice > 0 ? it.unitPrice : it.price/it.qty; }
function sortedReceipts(){ return cleanReceipts().filter(r => matchMode==="any" || storeFilter==="all" || chainOf(r.store)===storeFilter).sort((a,b)=> a.date.localeCompare(b.date) || String(a.savedAt).localeCompare(String(b.savedAt))); }
function chain(){
  const last = {}; let lnI = 0; const pts = []; const drv = {};
  for (const r of sortedReceipts()){
    const agg = {};
    for (const it of r.items){
      if (!isFood(it) || isSlip(it) || !(it.qty>0) || !(it.price>0)) continue;
      const mo = matchOf(r, it), k = mo.key;
      const a = (agg[k] ||= {name: matchMode==="any" && it.g ? it.g : it.name, unit:mo.u, spend:0, val:0, store:chainLabel(r.store)});
      a.spend += it.price; a.val += mo.p*it.price;
    }
    let food = 0, W = 0, S = 0, coveredSpend = 0; const matched = [];
    for (const k in agg){
      const a = agg[k]; a.up = a.val/a.spend; food += a.spend;
      const p = last[k];
      if (p && p.unit === a.unit){
        const rel = a.up/p.up, w = (a.spend + p.spend)/2;
        W += w; S += w*Math.log(rel); coveredSpend += a.spend;
        matched.push({k, name:a.name, unit:a.unit, from:p.up, fromDate:p.date, fromStore:p.store, toStore:a.store, to:a.up, rel, w});
      }
    }
    const step = W ? S/W : 0;
    for (const m of matched){ const d = (drv[m.k] ||= {name:m.name, ln:0}); d.ln += m.w/W*Math.log(m.rel); }
    lnI += step;
    matched.sort((x,y)=>y.w-x.w);
    pts.push({id:r.id, date:r.date, store:r.store, I:100*Math.exp(lnI), step:Math.exp(step)-1, matched, W, food, cover: food ? coveredSpend/food : 0, r});
    for (const k in agg) last[k] = {up:agg[k].up, spend:agg[k].spend, unit:agg[k].unit, date:r.date, store:agg[k].store};
  }
  // Which products account for the index's move (log contributions add up to ln(index/100)).
  pts.drivers = Object.values(drv).filter(d=>Math.abs(d.ln)>1e-6).sort((a,b)=>Math.abs(b.ln)-Math.abs(a.ln));
  return pts;
}
// Official pace reference: compound each day at the annual rate published for that day's month.
function paceIndex(from, to, pick){
  let ln = 0; let d = d2(from); const end = d2(to);
  while (d < end){
    const ym = d.toISOString().slice(0,7);
    const nextMonth = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth()+1, 1));
    const stop = nextMonth < end ? nextMonth : end;
    const n = (stop - d)/864e5;
    ln += n/365 * Math.log(1 + pick(officialFor(ym))/100);
    d = stop;
  }
  return 100*Math.exp(ln);
}
