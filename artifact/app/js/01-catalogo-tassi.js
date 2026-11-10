"use strict";
// ---------- Official data ----------
// Built-in fallback: September 2026 (Destatis 13 Oct 2026, Eurostat 16 Oct 2026).
// Later months arrive as documents in the shared "official" collection, one per month.
const FALLBACK = {month:"2026-09", label:"September 2026",
  de:{hicp:3.3, food:0.4, bev:-0.5, out:3.1, classes:{fish:4.5, dairy:-5.5, eggs:15.2, oils:-15.0, butter:-29.5, fruit:-4.9, veg:12.0, coffee:-3.3}},
  ea:{hicp:3.8, fat:1.3, proc:0.4, unproc:4.0},
  source:"Destatis press release 364 (13 Oct 2026); Eurostat euro indicators (16 Oct 2026)"};
const CATS = [
  {k:"bread",  n:"Bread & cereals",           coicop:"01.1.1", ea:"proc"},
  {k:"meat",   n:"Meat",                       coicop:"01.1.2", ea:"unproc"},
  {k:"fish",   n:"Fish & seafood",             coicop:"01.1.3", ea:"unproc"},
  {k:"dairy",  n:"Milk, cheese & dairy",       coicop:"01.1.4", ea:"proc"},
  {k:"eggs",   n:"Eggs",                       coicop:"01.1.4.7", ea:"proc"},
  {k:"oils",   n:"Oils & fats",                coicop:"01.1.5", ea:"proc"},
  {k:"butter", n:"Butter",                     coicop:"01.1.5.1", ea:"proc"},
  {k:"fruit",  n:"Fruit & nuts",               coicop:"01.1.6", ea:"unproc"},
  {k:"veg",    n:"Vegetables & pulses",        coicop:"01.1.7", ea:"unproc"},
  {k:"sweets", n:"Sugar, jam & sweets",        coicop:"01.1.8", ea:"proc"},
  {k:"other",  n:"Other food",                 coicop:"01.1.9", ea:"proc"},
  {k:"coffee", n:"Coffee, tea & cocoa",        coicop:"01.2.1", ea:"proc"},
  {k:"drinks", n:"Juices, water & soft drinks",coicop:"01.2.2", ea:"proc"},
  {k:"out",    n:"Cafés & eating out",         coicop:"11.1.1", ea:"hicp"},
  {k:"nonfood",n:"Non-food items",             coicop:"other",  ea:"hicp"},
];
const CAT = Object.fromEntries(CATS.map(c => [c.k, c]));
const EXCLUDED = "excluded";
const MONTHS_EN = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];

let official = {[FALLBACK.month]: FALLBACK};
let overrides = null; // {month, rates}
function monthKeys(){ return Object.keys(official).sort(); }
function latestOfficial(){ const k = monthKeys(); return official[k[k.length-1]]; }
// The release that applies to a calendar month: that month if published, else the latest one before it, else the earliest.
function officialFor(ym){ const k = monthKeys(); let pick = k[0]; for (const m of k) if (m <= ym) pick = m; return official[pick]; }
function classRates(o){
  const out = {};
  for (const c of CATS){
    const v = o.de?.classes?.[c.k];
    if (typeof v === "number") out[c.k] = {r:v, fb:false};
    else out[c.k] = {r: c.k==="drinks" ? (o.de.bev ?? o.de.food) : c.k==="nonfood" ? o.de.hicp : c.k==="out" ? (o.de.out ?? o.de.hicp) : o.de.food, fb:true};
  }
  return out;
}
function effective(o){
  o = o || latestOfficial();
  const cr = classRates(o); const r = {eaProc:o.ea.proc, eaUnproc:o.ea.unproc, eaHICP:o.ea.hicp};
  for (const k in cr) r[k] = cr[k].r;
  const isLatest = o === latestOfficial();
  if (isLatest && overrides && overrides.month === o.month && overrides.rates) Object.assign(r, overrides.rates);
  return {r, cr, o};
}
function eaRate(c, r){ return c.ea === "unproc" ? r.eaUnproc : c.ea === "hicp" ? r.eaHICP : r.eaProc; }
