"use strict";
// =====================================================================
// Kitchen (pantry): what was bought recently, minus meals logged and items marked used up
// =====================================================================
let pantryWin = 7, pantryDoc = {used:{}}, meals = [], pins = new Set(), lastUsedUndo = null;
// Typical shelf life in days, unopened and stored properly — a guide, not a use-by date.
const SHELF = [
  [/fish finger|stäbchen|frozen|tiefk|\btk\b/, 90],
  [/smoothie|true fruits/, 10], [/juice|saft|nektar/, 120], [/oat drink|haferdrink|uht|h-sahne|cream/, 120],
  [/tuna|thunf|tinned|canned|passata|chickpea|kichererb|sweetcorn|gemüsemais|olive|artichoke|artis|baby corn|maiskölb|maiskoelb|dried tom|tomatensauce|tomato sauce|chili crunch|kimchi/, 365],
  [/freeze-dried|gefriergetr/, 365],
  [/salmon|lachs|fish|fisch/, 2], [/chicken|hähn|haehn/, 3], [/ham|schinken|crudo|salami/, 7],
  [/raspberr|himbeer|berries|beeren/, 3],
  [/spinach|spinat|rocket|rucola|lettuce|salat|basil|basilik|chives|schnittk|herb|kräuter|spring onion|lauchzw/, 4],
  [/mushroom|champign/, 4], [/avocado/, 4], [/banana|banane/, 5], [/mango/, 5], [/broccoli|brokkoli|cauliflower|blumenkohl/, 5],
  [/cherry tom|date tom|datteltom|tomato|tomate|cucumber|gurke|courgette|zucchini|aubergine|fennel|fenchel/, 7],
  [/kiwi/, 10], [/pomegranate|granat/, 14], [/lemon|zitron/, 21], [/apple|apfel/, 30], [/carrot|karott|beetroot|rote ?be/, 21],
  [/potato|kartoffel|kart\./, 30], [/pumpkin|kürbis|hokkaido/, 60], [/ginger|ingwer/, 21],
  [/fresh whole milk|low-fat milk|\bmilk\b|milch\b|frimil/, 7],
  [/mozzarella|cottage/, 7], [/yogurt|yoghurt|joghurt|skyr|quark|kefir|mousse|pudding|soft cheese|frischk/, 14],
  [/feta/, 21], [/grana|parmig|parmesan/, 60], [/cheese|käse|kaese/, 21],
  [/egg|eier/, 21], [/tofu|tempeh|valess|schnitzel/, 21],
  [/crispbread|knäcke|vital/, 120],
  [/pretzel|laugen|\broll|brötchen|bread/, 2], [/pinsa|pizza dough|pizzateig/, 10], [/gnocchi|knödel|dumpling|udon/, 30],
  [/pasta|spaghetti|rice|reis|couscous|oat|flocken|muesli|müsli|flour|lentil cake|waffel|waffles|noodle|nudel/, 365],
  [/nut|nüss|seed|samen|chia|pistach|pinien|almond|mandel|walnut|maroni|chestnut/, 180],
  [/chocolate|schoko|bueno|riegel|pingui|gumm|haribo|sweets|bliss|energy ball|dates|datteln|honey|honig|spread|aufstr|jam/, 180],
  [/spice|gewürz|zimt|cinnamon|gyros/, 365],
];
const SHELF_CAT = {veg:7, fruit:7, dairy:14, meat:3, fish:2, bread:5, drinks:120, sweets:180, other:60, oils:180, butter:30, eggs:21, coffee:365};
function shelfDays(it){ const t = ((it.g||"") + " " + it.name).toLowerCase(); for (const [re, d] of SHELF) if (re.test(t)) return d; return SHELF_CAT[it.cat] || 30; }
function lineRef(r, idx){ return r.id + "#" + idx; }
function usedByMeals(){ const m = {}; for (const ml of meals) for (const u of (ml.uses||[])) for (const l of (u.lines||[])) m[l.ref] = (m[l.ref]||0) + (Number(l.g)||0); return m; }
function buildPantry(win){
  const today = todayISO(), usedG = usedByMeals(), items = {};
  for (const r of cleanReceipts()){
    const age = days(r.date, today); if (age > win || age < 0) continue;
    r.items.forEach((it0, idx) => {
      const it = withLib(r, it0);
      if (!isFood(it) || /beleg|theke|bedien/i.test(it.name)) return;
      const ref = lineRef(r, idx); if (pantryDoc.used?.[ref]) return;
      const wu = weightPerUnit(it);
      const g = wu ? (it.qty||1)*wu.w*(it.ep > 0 && it.ep <= 1 ? it.ep : 1)*1000 : null;
      const left = g != null ? Math.max(0, g - (usedG[ref]||0)) : null;
      if (g != null && left < Math.max(10, g*0.05)) return;
      const shelf = shelfDays(it), dl = shelf - age;
      if (dl < -Math.max(2, shelf*0.5)) return;               // long past its shelf life: presumed eaten or gone
      const key = (it.g || it.name).toLowerCase().trim() + (it.bio ? "|bio" : "");
      const P = (items[key] ||= {key, name: it.g || it.name, bio: !!it.bio, cat: it.cat, lines: [], g: 0, left: 0, val: 0, unknown: false, per: {}, mic: {}, _w: 0, ns: nsOf(it)?.grade || "", noNut: false, ct: co2Type(it)});
      P.lines.push({ref, date: r.date, g, left, dl, shelf, store: chainLabel(r.store)});
      if (g == null) P.unknown = true; else { P.g += g; P.left += left; P.val += it.price*(left/g); }
      if (!it.nut) P.noNut = true;
      const w = left || 100;
      for (const n of NUT){ if (n.calc) continue; P.per[n.k] = (P.per[n.k]||0) + (it.nut ? per100(n, it) : 0)*w; }
      for (const m of MIC) P.mic[m.k] = (P.mic[m.k]||0) + (Number(it.mic?.[m.k])||0)*w;
      P._w += w;
      if (it.wg != null){ P.wgW = (P.wgW||0) + it.wg*w; P.grainW = (P.grainW||0) + w; }
    });
  }
  const list = Object.values(items).map(P => {
    for (const k in P.per) P.per[k] /= P._w; for (const k in P.mic) P.mic[k] /= P._w;
    if (P.grainW) P.wg = P.wgW/P.grainW;
    P.lines.sort((a,b)=>a.dl-b.dl);
    P.dl = P.lines[0].dl;
    P.ppg = P.left > 0 ? P.val/P.left : null;
    return P;
  }).sort((a,b)=>a.dl-b.dl || a.name.localeCompare(b.name));
  list.forEach((P,i) => P.id = "p"+(i+1));
  return list;
}
function dueChip(dl){
  const today = todayISO();
  if (dl < 0) return `<span class="due now">past its usual shelf life</span>`;
  if (dl === 0) return `<span class="due now">use today</span>`;
  if (dl <= 2) return `<span class="due now">use by ${weekday(addDays(today, dl))}</span>`;
  if (dl <= 7) return `<span class="due soon">use by ${weekday(addDays(today, dl))}</span>`;
  return `<span class="due ok">keeps ${dl >= 60 ? "~"+Math.round(dl/30)+" months" : dl >= 21 ? "~"+Math.round(dl/7)+" weeks" : dl+" days"}</span>`;
}
function fmtGrams(g){ return g >= 1000 ? (g/1000).toLocaleString("de-DE",{maximumFractionDigits:1})+" kg" : Math.round(g)+" g"; }
function renderPantry(){
  const card = $("pantryCard");
  $("pantryWin").querySelectorAll("button").forEach(b => b.setAttribute("aria-pressed", +b.dataset.pw === pantryWin));
  const list = buildPantry(pantryWin);
  if (!list.length){ card.innerHTML = `<p class="empty">No food bought in the last ${pantryWin} days. Add a receipt or look further back.</p>`; return; }
  const row = P => `<div class="prow"><div class="nm">${P.ns?`<span class="ns ${P.ns}" style="margin:0 6px 0 0">${P.ns}</span>`:""}${esc(P.name)}${P.bio?" ·bio":""}
      <small>${P.unknown && !P.left ? "amount unknown" : "≈ "+fmtGrams(P.left)+" left"}${P.ppg ? " · "+eur(P.ppg*1000)+"/kg" : ""} · bought ${esc(weekday(P.lines[0].date))} ${esc(fmtDay(P.lines[0].date))}, ${esc(P.lines[0].store)}</small></div>
      ${dueChip(P.dl)}
      <div class="row" style="gap:6px;flex-wrap:nowrap"><button type="button" data-pin="${esc(P.key)}" aria-pressed="${pins.has(P.key)}" aria-label="Include ${esc(P.name)} in the next suggestions">Include</button><button type="button" data-usedup="${esc(P.key)}" aria-label="Mark ${esc(P.name)} as used up">Used up</button></div></div>`;
  const soon = list.filter(P=>P.dl<=2), week = list.filter(P=>P.dl>2 && P.dl<=7), longer = list.filter(P=>P.dl>7);
  card.innerHTML = `${lastUsedUndo ? `<p class="banner" style="margin:0 0 8px">Marked ${esc(lastUsedUndo.name)} as used up. <button type="button" class="xlink" id="undoUsed">Undo</button></p>` : ""}
    ${soon.length ? `<div class="pgroup"><h3>Use soon</h3>${soon.map(row).join("")}</div>` : ""}
    ${week.length ? `<div class="pgroup"><h3>This week</h3>${week.map(row).join("")}</div>` : ""}
    ${longer.length ? `<details class="pgroup" ${soon.length + week.length < 4 ? "open" : ""}><summary><h3 style="display:inline">Keeps longer (${longer.length})</h3></summary>${longer.map(row).join("")}</details>` : ""}
    <p class="note" style="margin-top:10px">Amounts are what you bought minus meals logged here and items marked used up. Use-by days are typical shelf lives for each kind of food, counted from the receipt date: a guide only, so check the pack. “Include” makes the next suggestions use it.</p>`;
}
$("pantryWin").addEventListener("click", e => { const b = e.target.closest("button[data-pw]"); if (!b) return; pantryWin = +b.dataset.pw; renderPantry(); });
$("pantryCard").addEventListener("click", async e => {
  if (e.target.id === "undoUsed" && lastUsedUndo){
    const used = {...(pantryDoc.used||{})}; for (const r of lastUsedUndo.refs) delete used[r];
    lastUsedUndo = null; await savePantry(used); return;
  }
  const pk = e.target.dataset?.pin;
  if (pk){ pins.has(pk) ? pins.delete(pk) : pins.add(pk); renderPantry(); renderPlan(); return; }
  const uk = e.target.dataset?.usedup;
  if (uk){
    const P = buildPantry(pantryWin).find(x => x.key === uk); if (!P) return;
    const used = {...(pantryDoc.used||{})}; const today = todayISO(); for (const l of P.lines) used[l.ref] = today;
    pins.delete(uk); lastUsedUndo = {name: P.name, refs: P.lines.map(l=>l.ref)};
    await savePantry(used);
  }
});
async function savePantry(used){
  pantryDoc = {...pantryDoc, used};
  renderPantry(); renderGlance();
  if (db && uid){ try { await db.collection(COL).doc("pantry").set({kind:"pantry", used}); } catch(_){} }
}
