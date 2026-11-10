"use strict";
// ---------- Photo → items ----------
$("photo").addEventListener("change", e => {
  photoFile = e.target.files?.[0] || null;
  if (!photoFile) return;
  $("previewImg").src = URL.createObjectURL(photoFile);
  $("previewBox").hidden = false;
  $("readStatus").textContent = photoFile.name;
  $("readBtn").disabled = !sample;
  $("aiStatus").className = "status";
  $("aiStatus").textContent = sample ? "Ready. Tap “Read receipt”." : "Reading photos is not available in this view.";
});
const RECEIPT_CLASSES = `Classes (use the key):
bread = bread, rolls, flour, rice, pasta, noodles, cereals, muesli, dumplings (Knödel), cakes, biscuits
meat = all meat, poultry, sausage, ham
fish = fish, seafood, canned tuna
dairy = milk, yogurt, kefir, cheese, cream, quark, plant-based milk/yogurt alternatives
eggs = eggs
oils = cooking oils, margarine
butter = butter
fruit = fresh/dried fruit, nuts, avocados
veg = vegetables, salad, potatoes, pulses (chickpeas, beans, lentils), mushrooms, kimchi/sauerkraut, sweetcorn
sweets = sugar, jam, honey, chocolate, sweets, chocolate bars, ice cream, energy/bliss balls
other = sauces, spices, salt, soups, baby food, ready meals, seeds, tofu, tempeh, other food
coffee = coffee, tea, cocoa
drinks = mineral water, juices, smoothies, soft drinks, alcohol-free wine and beer
out = drinks and food made to order at a café, bakery counter seating, restaurant or takeaway (espresso, flat white, a slice of cake eaten there)
nonfood = household, toiletries, clothing, alcoholic drinks, tobacco, anything not food
excluded = bottle deposit (Pfand), deposit returns (negative), carrier bags (Tragetasche), coupons/discount lines`;
const PROMPT = `You are reading a photo of a grocery receipt (often German: ALDI, LIDL, REWE, EDEKA, dm…). Extract every purchased line and classify it into an HICP / ECOICOP food class.

${RECEIPT_CLASSES}

Rules:
- One entry per printed product line, in receipt order. Do not merge repeated lines.
- If a weight line follows (e.g. "0,802 kg x 1,99 EUR/kg"), set unit "kg", qty to the kg, unitPrice to the per-kg price, and attach it to the product above.
- Otherwise unit "pc", qty 1 (or the printed multiplier, e.g. "2 x 1,29"), unitPrice = price / qty.
- price is the line total in euros as a number. Discount lines: put them as excluded with a negative price.
- A line that is the total of a separate counter slip (e.g. "Beleg Käse", "Bedienung", "Theke") stays one line, classified by what the counter sells.
- g = a short generic English name for comparing the same kind of product across shops, without brand or "organic" (e.g. "Apple juice", "Mozzarella", "Cherry tomatoes", "Oat drink", "Bananas"). Use the same wording for the same kind of product.
- For each food line also give w, wSrc, ep and nut:
  w = net weight in kg of one pack or piece (drained weight for tinned or jarred goods; 1 l milk = 1.03); for weighed lines give 1. wSrc = "label" if the size is printed, else "est" for a typical weight.
  ep = edible fraction (bananas 0.65, mango 0.7, eggs 0.88, packaged foods 1).
  nut = typical values per 100 g edible part: {"kcal","p","f","sf","c","s","fib","salt"} (protein, fat, saturated fat, available carbohydrate, sugars, fibre, salt in g).
  fat2 = typical per 100 g {"mufa","pufa","n3"} (monounsaturated, polyunsaturated, omega-3 in g); wg = for grain products only, % wholegrain (0–100).
  mic = typical per 100 g edible part: {"vc" vitamin C mg,"va" vitamin A µg RAE,"vd" vitamin D µg,"b12" µg,"fol" folate µg,"ca" calcium mg,"fe" iron mg,"mg" magnesium mg,"k" potassium mg,"zn" zinc mg}.
  nsType = Nutri-Score category: "bev" (drinks incl. milk, kefir, plant drinks, juices), "water", "fat" (oils, butter, spreads, cream, nuts, seeds), "cheese", "redmeat" (beef, pork, lamb and their products), else "food". fvl = % fruit, vegetables and legumes (not potatoes, nuts or soy products).
- ct = climate type of the product, the closest of: ${Object.keys(CO2T).join(", ")}.
- bio = true if organic (Bio, Öko, Alnatura, demeter…), else false.
- size = the pack size as printed in the name or as you reliably know it for that product (e.g. "1 l", "500 g", "125 g", "6 pc"; "1 pc" for fruit or vegetables sold by the piece); "" if unsure or if the line is weighed.
- code = the article number printed before the name, or "" if none. Copy it exactly; it is used to match the same product across receipts.
- date as YYYY-MM-DD; total = the amount paid (Summe/Betrag/Total) as a number, or null.

Reply with only JSON:
{"store":"ALDI SÜD Frankfurt","date":"2026-10-21","total":103.31,"items":[{"code":"229396","name":"Bananen Bio","qty":0.802,"unit":"kg","unitPrice":1.99,"price":1.6,"cat":"fruit","g":"Bananas","bio":true,"size":"","w":1,"wSrc":"label","ep":0.65,"nut":{"kcal":93,"p":1.2,"f":0.2,"sf":0.1,"c":20,"s":17,"fib":2,"salt":0}},{"code":"536425","name":"Bio-Apfelsaft 1l","qty":1,"unit":"pc","unitPrice":1.55,"price":1.55,"cat":"drinks","g":"Apple juice","bio":true,"size":"1 l","w":1.04,"wSrc":"label","ep":1,"nut":{"kcal":45,"p":0.1,"f":0.1,"sf":0,"c":10,"s":10,"fib":0,"salt":0}}]}`;
$("readBtn").onclick = async () => {
  if (!sample || !photoFile) return;
  ctl = new AbortController();
  $("readBtn").disabled = true; $("stopBtn").hidden = false;
  $("aiStatus").className = "status"; $("aiStatus").textContent = "Reading the receipt… this takes 20–60 seconds.";
  try {
    const known = [...new Set(cleanReceipts().flatMap(r=>r.items.map(i=>i.g).filter(Boolean)))].slice(0,250);
    const mi = memoryIndex(), kl = knownList(mi);
    const memTxt = kl ? `\n\nProducts this household has bought before (store: article number, receipt text = generic name). For a line whose article number matches one of these at the same store (or, without a number, whose text matches), give only {"code","name","qty","unit","unitPrice","price","known":true}: the rest is filled in from memory. Give all fields for every other line.\n${kl}` : "";
    const out = await sample.json(PROMPT + (known.length ? "\n\nGeneric names already in use (reuse one exactly when it is the same kind of product):\n" + known.join("; ") : "") + memTxt, {images:[photoFile], signal:ctl.signal});
    const store = String(out?.store||"");
    let items = Array.isArray(out?.items) ? out.items.map(i => ({
      code:String(i.code||""), name:String(i.name||"Item"), qty:Number(i.qty)||1, unit:i.unit==="kg"?"kg":"pc",
      unitPrice:Number(i.unitPrice)||0, price:round2(Number(i.price)||0),
      cat: (CAT[i.cat] || i.cat===EXCLUDED) ? i.cat : "other",
      g: typeof i.g === "string" ? i.g.trim().slice(0,60) : "", bio: !!i.bio, size: typeof i.size === "string" ? i.size.trim().slice(0,20) : "", _e:i})) : [];
    items.forEach(it => { const e = it._e; delete it._e; if (CO2T[e?.ct]) it.ct = e.ct; if (isFood(it) && e && e.nut && typeof e.nut === "object") applyNut(it, e); it._known = !!e?.known; });
    let nMem = 0; const todoCls = [];
    items = items.map(it => {
      const m = memFind(mi, store, it);
      if (m && (it._known || !it.nut || m.raw.nut)){ nMem++; return fromMemory(it, m); }
      if (it._known || (isFood(it) && !it.nut && !isSlip(it))) todoCls.push(it);
      return it;
    });
    if (todoCls.length){ $("aiStatus").textContent = `Read ${items.length} lines; looking up ${todoCls.length} more…`; try { await classifyItems(store, todoCls, ctl.signal); } catch(e){ if (e?.code === "cancelled") throw e; } }
    items = items.map(it => { delete it._known; const m = withLib({store}, it); return {...m, _orig: {cat:m.cat, g:m.g||"", bio:!!m.bio, size:m.size||"", ct: co2Type(m)}}; });
    items.forEach(i => { if (!i.unitPrice && i.qty) i.unitPrice = round2(i.price/i.qty); });
    if (!items.length) throw {code:"empty"};
    draft = {store, date:/^\d{4}-\d{2}-\d{2}$/.test(out.date||"") ? out.date : "", total:Number(out.total)||null, items};
    draftIsExample = false;
    $("aiStatus").textContent = `Found ${items.length} lines${nMem ? `, ${nMem} recognised from earlier receipts` : ""}. Check the classes below, then save.`;
    renderAll();
    $("draftSec").scrollIntoView({behavior:"smooth", block:"start"});
  } catch(e){
    $("aiStatus").className = "status err";
    const m = {cancelled:"Stopped.", not_granted:"Reading photos needs your permission to use Claude on this page.", rate_limited:"Too many requests just now. Wait a minute and try again.",
      image_rejected:"That photo could not be used. Try a JPEG or PNG under 20 MB.", images_unavailable:"This view cannot send photos to Claude.",
      invalid_json:"The receipt could not be read cleanly. Try a sharper, flatter photo.", empty:"No items were found. Try a sharper photo with the whole receipt in frame."};
    $("aiStatus").textContent = m[e?.code] || "Something went wrong reading the receipt. Try again.";
    if (e?.code==="cancelled") $("aiStatus").className = "status";
  } finally { $("readBtn").disabled = !photoFile; $("stopBtn").hidden = true; }
};
$("stopBtn").onclick = () => ctl?.abort();
