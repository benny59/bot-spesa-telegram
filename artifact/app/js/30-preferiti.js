"use strict";
// ---------- Preferiti di Spesa: importazione (file JSON) e collegamento automatico ----------
// Il file lo esporta la PWA Spesa (Preferiti → "Esporta preferiti (JSON)"): solo nome, categoria, codice a barre.
// Una riga di scontrino si collega a un preferito solo se i primi termini della descrizione coincidono con il suo nome
// (la descrizione è tagliata, quindi si confrontano gli inizi delle parole). In caso di dubbio non si collega nulla.
function terminiNome(s) {
  return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, " ").split(" ")
    .filter(w => w.length >= 3 && !/^\d+$/.test(w) && !["con", "del", "dei", "per", "bio", "gr", "kg"].includes(w));
}
function terminiUguali(r, f) {          // r: parola dello scontrino (forse tagliata), f: parola del preferito
  if (r === f) return true;
  return Math.min(r.length, f.length) >= 4 && (r.startsWith(f) || f.startsWith(r));
}
const cacheTermini = new Map();   // i preferiti letti dal database non si possono modificare: la cache sta fuori
function terminiPref(f) { let t = cacheTermini.get(f.d); if (!t) { t = terminiNome(f.d); cacheTermini.set(f.d, t); } return t; }
function trovaPreferito(nome, lista) {
  const r = terminiNome(nome);
  if (!r.length) return null;
  let best = null, ambiguo = false;
  for (const f of lista) {
    const ft = terminiPref(f);
    if (!ft.length || ft.length > r.length) continue;
    if (!ft.every((w, i) => terminiUguali(r[i], w))) continue;
    if (!best || ft.length > terminiPref(best).length) { best = f; ambiguo = false; }
    else if (ft.length === terminiPref(best).length && f.d.toLowerCase() !== best.d.toLowerCase()) ambiguo = true;
  }
  return best && !ambiguo ? best : null;
}
// Applica ai prodotti di una bozza: nome generico (g) e codice a barre (ean) dal preferito, se non c'è già una regola.
function applicaPreferiti(items) {
  let n = 0;
  if (!favs.length) return n;
  items.forEach(it => {
    if (it.cat === EXCLUDED || it._mem) return;
    const f = trovaPreferito(it.name, favs);
    if (!f) return;
    it.g = f.d; if (f.e) it.ean = f.e; n++;
  });
  return n;
}
function leggiFileFavoriti(testo) {
  const o = JSON.parse(testo);
  const arr = Array.isArray(o) ? o : (o && Array.isArray(o.favorites) ? o.favorites : null);
  if (!arr) throw new Error("formato");
  const visti = new Set(), out = [];
  arr.forEach(x => {
    const d = String((x && (x.description || x.d)) || "").trim().slice(0, 80);
    const e = String((x && (x.gtin || x.ean || x.e)) || "").replace(/\D/g, "");
    if (!d || visti.has(d.toLowerCase() + "|" + e)) return;
    visti.add(d.toLowerCase() + "|" + e);
    out.push({d, e: /^\d{8,14}$/.test(e) ? e : ""});
  });
  return out;
}
function statoPreferiti() {
  $("favStatus").textContent = favs.length ? t("fav.count", {n: favs.length, e: favs.filter(f => f.e).length}) : t("fav.none");
}
$("favFile").addEventListener("change", async e => {
  const f = e.target.files && e.target.files[0]; if (!f) return;
  try {
    favs = leggiFileFavoriti(await f.text());
    statoPreferiti();
    if (db && uid) await db.collection(COL).doc("favs").set({kind: "favs", id: "favs", favorites: favs, at: new Date().toISOString()});
  } catch (err) { $("favStatus").textContent = t("fav.err"); }
  e.target.value = "";
});
statoPreferiti();
