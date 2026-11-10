"use strict";
// ---------- Receipt hygiene: food lines, store chains, duplicates ----------
// A counter slip ("Beleg Käse", deli or bakery counter) is the total of several items, so it is never compared as one product.
function isSlip(it){ return /beleg|theke|bedien|counter/i.test(it.name + " " + (it.g||"")); }
function isFood(it){ return it.cat !== EXCLUDED && it.cat !== "nonfood" && it.cat !== "out" && !!CAT[it.cat]; }
function chainOf(store){ return (String(store||"").trim().split(/\s+/)[0] || "Store").toLowerCase(); }
function chainLabel(store){ const w = String(store||"").trim().split(/\s+/)[0] || "Store"; return w.length <= 4 ? w.toUpperCase() : w[0].toUpperCase() + w.slice(1).toLowerCase(); }
function receiptSum(r){ return round2(r.items.reduce((a,i)=>a+(Number(i.price)||0),0)); }
function sig(r){ return [r.date, chainOf(r.store), (r.total ?? receiptSum(r)).toFixed(2), r.items.length].join("|"); }
// Receipts saved twice (same day, store, total and line count): keep the first, flag the rest.
function dupIds(){
  const seen = new Set(), dups = new Set();
  for (const r of [...receipts].sort((a,b)=>String(a.savedAt).localeCompare(String(b.savedAt)))){
    const k = sig(r); if (seen.has(k)) dups.add(r.id); else seen.add(k);
  }
  return dups;
}
// Every analysis reads receipts through product memory (your rules, typical values for corrected products, label data).
let memVer = 0, memCache = null;
function memReceipts(){
  if (memCache && memCache.v === memVer && memCache.src === receipts) return memCache.list;
  const list = receipts.map(r => ({...r, items: r.items.map(it => withLib(r, it))}));
  memCache = {v: memVer, src: receipts, list}; return list;
}
function cleanReceipts(){ const d = dupIds(); return memReceipts().filter(r => !d.has(r.id)); }
function stripItem(it){ const o = {}; for (const k in it) if (k[0] !== "_") o[k] = it[k]; return o; }
let storeFilter = "all";
let matchMode = "same";     // "same": same article in the same chain (as official statistics do); "any": comparable product anywhere
let mergeOrganic = false;
// Pack size as printed ("1 l", "500 g", "2 pc") → quantity in kg, l or pieces.
function parseSize(s){
  const m = String(s||"").replace(",",".").match(/([\d.]+)\s*(kg|g|l|ml|cl|pc|pcs|stk|st)\b/i); if (!m) return null;
  let q = parseFloat(m[1]), u = m[2].toLowerCase();
  if (u==="g"){ q/=1000; u="kg"; } else if (u==="ml"){ q/=1000; u="l"; } else if (u==="cl"){ q/=100; u="l"; } else if (u!=="kg" && u!=="l") u="pc";
  return q > 0 ? {q,u} : null;
}
// Price per kg, per litre or per piece where the size is known; otherwise per pack.
function compPrice(it){
  if (it.unit === "kg") return {p: unitPriceOf(it), u:"kg"};
  const per = it.price/(it.qty||1), sz = parseSize(it.size);
  return sz ? {p: per/sz.q, u: sz.u} : {p: per, u: "pack"};
}
function genKey(it){ return it.g ? String(it.g).toLowerCase().trim() + (mergeOrganic ? "" : (it.bio ? "|organic" : "|conv")) : null; }
function unitLabel(u){ return u==="kg" ? "per kg" : u==="l" ? "per litre" : u==="pc" ? "per piece" : "per pack"; }
function fmtUP(p,u){ return eur(p) + (u==="kg"?"/kg":u==="l"?"/l":u==="pc"?"/pc":""); }
// Key and comparable price used by the index for the current matching mode.
function matchOf(r, it){
  if (matchMode === "any" && it.g){
    const cp = compPrice(it);
    // Without a known pack size, only the same article in the same chain is comparable.
    const key = cp.u === "pack" ? itemKey(r.store,it) + "|pack" : "g|" + genKey(it) + "|" + cp.u;
    return {key, p: cp.p, u: cp.u};
  }
  return {key: itemKey(r.store,it), p: unitPriceOf(it), u: it.unit};
}
