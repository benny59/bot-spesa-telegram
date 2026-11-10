"use strict";
// ---------- Basket math (official rates on your mix) ----------
function basketFrom(list, eff){
  eff = eff || effective();
  const spend = {}; let total = 0;
  for (const r of list) for (const it of r.items){
    if (!isFood(it)) continue;
    spend[it.cat] = (spend[it.cat]||0) + it.price; total += it.price;
  }
  let de = 0, ea = 0; const rows = [];
  for (const c of CATS){ const s = spend[c.k]; if (!s) continue;
    const w = s/total, rr = eff.r[c.k]; de += w*rr; ea += w*eaRate(c, eff.r);
    rows.push({c, s, w, r:rr, fb:eff.cr[c.k].fb && rr===eff.cr[c.k].r, contrib:w*rr});
  }
  rows.sort((a,b)=>b.s-a.s);
  return {total, de, ea, rows};
}
function activeBasket(){
  const clean = cleanReceipts();
  if (clean.length) return {list:clean, label: clean.length+" saved receipt"+(clean.length>1?"s":"")};
  if (!draft) return {list:[], label:""};
  return {list:[draft], label: draftIsExample ? "Example: your 21 Oct ALDI receipt (not saved yet)" : "Unsaved receipt"};
}
