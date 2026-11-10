"use strict";
// ---------- Longevity food groups ----------
// Per adult per day (2,000 kcal). Minimums and limits from the German Nutrition Society's 2024 food-based guidelines,
// the meta-analyses behind them, and the food-choice life-expectancy model of Fadnes et al. (PLOS Med 2022),
// where legumes, whole grains and nuts gave the largest gains and red and processed meat the largest losses.
const LONG = [
  {k:"veg",    n:"Vegetables",            min:400, w:25, f: x => x.cat === "veg" && !["potatoes","lentils","pulsestin"].includes(x.ct) ? 1 : 0, src:"DGE: 3 portions, 400 g"},
  {k:"fruit",  n:"Fruit",                 min:250, w:15, f: x => x.cat === "fruit" && !["nuts","seeds","dried","freezedried","nutbutter"].includes(x.ct) ? 1 : 0, src:"DGE: 2 portions, 250 g"},
  {k:"leg",    n:"Legumes, tofu, tempeh", min:100, w:20, f: x => x.ct === "lentils" || /legume pasta|lentil pasta|chickpea pasta|bean pasta/i.test(x.name||"") ? 2.5 : ["pulsestin","tofu","tempeh"].includes(x.ct) ? 1 : 0, src:"cooked weight; DGE minimum 125 g a week, Fadnes optimum 200 g a day"},
  {k:"wg",     n:"Whole grains",          min:90,  w:15, f: x => x.wg != null ? Math.max(0, Math.min(100, x.wg))/100 : 0, src:"as bought; 90 g a day (3 portions) in Aune 2016"},
  {k:"nuts",   n:"Nuts and seeds",        min:25,  w:15, f: x => ["nuts","seeds","nutbutter"].includes(x.ct) ? 1 : 0, src:"DGE and Fadnes: a handful, 25 g"},
  {k:"fish",   n:"Fish",                  min:30,  w:12, f: x => ["fishfarm","fishwild","fishfing","tuna","prawns"].includes(x.ct) ? 1 : 0, src:"DGE: 1–2 portions a week (about 200 g)"},
  {k:"meat",   n:"Meat, all kinds",       max:43,  w:15, f: x => ["beef","mince","pork","chicken","sausage","ham"].includes(x.ct) ? 1 : 0, src:"DGE: at most 300 g a week"},
  {k:"rpm",    n:"Red and processed meat",max:15,  w:15, f: x => ["beef","mince","pork","sausage","ham"].includes(x.ct) ? 1 : 0, src:"as little as possible; Fadnes optimum 0"},
  {k:"sdrink", n:"Juice and soft drinks", max:100, w:10, f: x => ["juice","oj","smoothie","soft"].includes(x.ct) ? 1 : 0, src:"free sugars; WHO under 10 %, ideally 5 % of energy"},
];
const ANIMAL_CT = new Set(["beef","mince","pork","chicken","sausage","ham","fishfarm","fishwild","fishfing","tuna","prawns","milk","yogurt","quark","cream","butter","cheese","hardcheese","freshcheese","feta","eggs","dessert"]);
const isPlantCt = ct => !ANIMAL_CT.has(ct);
// Grams of each group in a basket, from items carrying {cat, ct, wg, name} and an edible weight in kg.
function longGrams(items, kgOf){ const out = Object.fromEntries(LONG.map(L => [L.k, 0])); for (const it of items){ const kg = kgOf(it); if (!(kg > 0)) continue; for (const L of LONG) out[L.k] += L.f(it)*kg*1000; } return out; }
const LONG_PROMPT = "Longevity priorities (DGE 2024, large cohort meta-analyses): legumes most days, whole grains rather than refined, a handful of nuts or seeds daily, fish once or twice a week, little red meat and almost no processed meat, olive or rapeseed oil as the main fat, plenty of vegetables and fruit, little salt and added sugar.";

// Micronutrients per 100 g and the EU nutrient reference values (Regulation 1169/2011, adults).
const MIC = [
  {k:"vc",  n:"Vitamin C",  u:"mg", nrv:80},
  {k:"va",  n:"Vitamin A",  u:"µg", nrv:800},
  {k:"vd",  n:"Vitamin D",  u:"µg", nrv:5},
  {k:"b12", n:"Vitamin B12",u:"µg", nrv:2.5},
  {k:"fol", n:"Folate",     u:"µg", nrv:200},
  {k:"ca",  n:"Calcium",    u:"mg", nrv:800},
  {k:"fe",  n:"Iron",       u:"mg", nrv:14},
  {k:"mg",  n:"Magnesium",  u:"mg", nrv:375},
  {k:"k",   n:"Potassium",  u:"mg", nrv:2000},
  {k:"zn",  n:"Zinc",       u:"mg", nrv:10},
];
// ---- Nutri-Score (2023/24 algorithm) ----
function steps(v, th){ let p = 0; for (const t of th) if (v > t) p++; return p; }
const NS_FOOD_SUGAR = [3.4,6.8,10,14,17,20,24,27,31,34,37,41,44,48,51];
const NS_SALT = Array.from({length:20}, (_,i)=>+(0.2*(i+1)).toFixed(1));
const NS_PROT = [2.4,4.8,7.2,9.6,12,14,17];
const NS_FIB = [3.0,4.1,5.2,6.3,7.4];
function nutriScore(n, type, fvl, sweetener){
  if (!n) return null;
  type = type || "food"; fvl = Math.max(0, Math.min(100, Number(fvl)||0));
  const kJ = (n.kcal||0)*4.184, sug = n.s||0, sf = n.sf||0, fat = n.f||0, salt = n.salt||0, prot = n.p||0, fib = n.fib||0;
  if (type === "water") return {grade:"A", pts:0};
  if (type === "bev"){
    const N = steps(kJ,[30,90,150,210,240,270,300,330,360,390]) + steps(sug,[0.5,2,3.5,5,6,7,8,9,10,11]) + steps(sf,[1,2,3,4,5,6,7,8,9,10]) + steps(salt,NS_SALT) + (sweetener?4:0);
    const P = steps(prot,[1.2,1.5,1.8,2.1,2.4,2.7,3.0]) + steps(fib,NS_FIB) + (fvl>80?6:fvl>60?4:fvl>40?2:0);
    const pts = N - P;
    return {pts, grade: pts<=2 ? "B" : pts<=6 ? "C" : pts<=9 ? "D" : "E"};
  }
  const fvlP = fvl>80 ? 5 : fvl>60 ? 2 : fvl>40 ? 1 : 0;
  if (type === "fat"){
    const ratio = fat > 0 ? sf/fat*100 : 0;
    const N = steps(sf*37,[120,240,360,480,600,720,840,960,1080,1200]) + steps(sug,NS_FOOD_SUGAR) + steps(ratio,[10,16,22,28,34,40,46,52,58,64].map(x=>x-1e-9)) + steps(salt,NS_SALT);
    const P = (N < 7 ? steps(prot,NS_PROT) : 0) + steps(fib,NS_FIB) + fvlP;
    const pts = N - P;
    return {pts, grade: pts<=-6 ? "A" : pts<=2 ? "B" : pts<=10 ? "C" : pts<=18 ? "D" : "E"};
  }
  const N = steps(kJ,[335,670,1005,1340,1675,2010,2345,2680,3015,3350]) + steps(sug,NS_FOOD_SUGAR) + steps(sf,[1,2,3,4,5,6,7,8,9,10]) + steps(salt,NS_SALT);
  let protP = steps(prot,NS_PROT); if (type === "redmeat") protP = Math.min(protP, 2);
  const P = ((N < 11 || type === "cheese") ? protP : 0) + steps(fib,NS_FIB) + fvlP;
  const pts = N - P;
  return {pts, grade: pts<=0 ? "A" : pts<=2 ? "B" : pts<=10 ? "C" : pts<=18 ? "D" : "E"};
}
