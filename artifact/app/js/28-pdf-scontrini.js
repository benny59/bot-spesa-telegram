"use strict";
// ---------- Scontrino PDF (Coop, Tigros) → righe ----------
// Il PDF è testo: si legge con pdf.js (da cdnjs), senza modello. Il file e il testo grezzo NON vengono
// salvati: nella bozza finiscono solo negozio, data, totale e le righe (nome, prezzo). Carta, intestatario,
// punti e dati del pagamento vengono ignorati.
const PDFJS_URL = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js";
const PDFJS_WORKER = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
let pdfjsPromise = null;
function caricaPdfJs() {
  if (window.pdfjsLib) return Promise.resolve(window.pdfjsLib);
  if (!pdfjsPromise) pdfjsPromise = new Promise((ok, ko) => {
    const s = document.createElement("script");
    s.src = PDFJS_URL;
    s.onload = () => { window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER; ok(window.pdfjsLib); };
    s.onerror = () => { pdfjsPromise = null; ko({code: "pdfjs"}); };
    document.head.appendChild(s);
  });
  return pdfjsPromise;
}
// Testo del PDF → righe (si raggruppano i frammenti con la stessa altezza, da sinistra a destra).
async function righePdf(file) {
  const lib = await caricaPdfJs();
  const pdf = await lib.getDocument({data: new Uint8Array(await file.arrayBuffer())}).promise;
  const righe = [];
  for (let p = 1; p <= pdf.numPages; p++) {
    const tc = await (await pdf.getPage(p)).getTextContent();
    const gruppi = [];
    tc.items.forEach(it => {
      if (!it.str || !it.str.trim()) return;
      const y = it.transform[5], x = it.transform[4];
      let g = gruppi.find(g => Math.abs(g.y - y) < 2);
      if (!g) { g = {y, parti: []}; gruppi.push(g); }
      g.parti.push({x, s: it.str});
    });
    gruppi.sort((a, b) => b.y - a.y).forEach(g =>
      righe.push(g.parti.sort((a, b) => a.x - b.x).map(q => q.s).join(" ").replace(/\s+/g, " ").trim()));
  }
  return righe.filter(Boolean);
}
function numIt(s) {
  s = String(s);
  return Number(s.indexOf(",") >= 0 ? s.replace(/\./g, "").replace(",", ".") : s);
}
// Classe per parole chiave (il primo che corrisponde vince; il resto resta "other" e può essere chiesto al modello).
const REGOLE_CLASSE = [
  [/\b(SHOPPER|SACCHETT|BUSTA)/, EXCLUDED],
  [/\b(DETERS|SAPONE|CARTA IGIEN|SHAMPOO|DENTIFR|BIRRA|VINO|PROSECCO|GRAPPA|AMARO|LIQUOR|SIGARET|PIATTI|PULI|AMMORB|SPUGN|PILE\b)/, "nonfood"],
  [/\b(TONNO|SALMON|MERLUZZ|BACCAL|GAMBER|ACCIUG|PESCE|SGOMBR|ORATA|BRANZ|COZZE|VONGOL|TRANCI|SURIMI)/, "fish"],
  [/\b(MACINAT|MORTAD|WURSTEL|PROSC|SALAM|BRESAOL|POLLO|TACCHIN|MAIAL|SUINO|BOVIN|SALSICC|PANCETT|SPECK|COTOLETT|HAMBURG|FESA|ARROST|COTECH|BISTECC|VITELL|AGNELL)/, "meat"],
  [/\bUOV[AO]/, "eggs"],
  [/\bBURRO\b/, "butter"],
  [/\b(OLIO|MARGARIN)/, "oils"],
  [/\b(CREME|CRÉME|CREMA) DESSERT|\b(KIT ?KAT|CIOCCOL|CARAMEL|GELATO|MARMELL|CONFETT|MIELE|ZUCCHERO|NUTELLA|BARRETT)/, "sweets"],
  [/\b(MOZZ|RICOTT|LATTE|YOGURT|FORMAGG|PARMIG|GRANA|PECORIN|ASIAGO|GORGONZ|PANNA|MASCARP|STRACCH|SCAMORZ|KEFIR|FONTINA|EMMENT|PROVOL|BURRATA|TOMINO)/, "dairy"],
  [/\b(CAFF|THE\b|TISANA|CAMOMILL|CACAO)/, "coffee"],
  [/\b(ACQUA|SUCCO|BIBITA|COCA COLA|FANTA|SMOOTHIE|SPREMUTA)/, "drinks"],
  [/\b(PATAT|RAD\.|RADICCH|BROCCOL|POMODOR|INSALAT|ZUCCHIN|CAROT|CIPOLL|AGLIO|SPINAC|FINOCCH|CAVOL|PEPERON|MELANZAN|FUNGHI|CHAMPIGN|SEDANO|LATTUGA|RUCOLA|ZUCCA|FAGIOL|CECI|LENTICCH|PISELL|MAIS|CETRIOL|CARCIOF|ASPARAG|PORRI|BIETOL|RAVANELL|VERZA)/, "veg"],
  [/\b(KIWI|AVOCADO|BANAN|MEL[AE]\b|PER[AE]\b|ARANC|LIMON|FRAGOL|UVA\b|MANDARIN|CLEMENT|ANANAS|MANGO|PESCH|NOCI\b|MANDORL|NOCCIOL|PISTACC|DATTER|FICHI|CILIEGI|ANGURIA|MELONE|PRUGN)/, "fruit"],
  [/\b(PASTA|SPAGHETT|PENNE|FUSILLI|RIGATON|RISO\b|FARINA|PANE\b|GRISSIN|CRACKER|BISCOT|FROLLIN|MERENDIN|CORNETT|CROISS|SACHER|CROSTATA|TORTA|QUINOA|COUS|AVENA|FIOCCHI|CEREAL|MUESLI|GNOCCH)/, "bread"]
];
function classeDaNome(nome) {
  const n = String(nome).toUpperCase();
  for (const [re, c] of REGOLE_CLASSE) if (re.test(n)) return c;
  return "other";
}
const NOMI_CITTA = /([A-ZÀ-Ù' ]{3,}?)\s*\(([A-Z]{2})\)/;
function titolo(s) { return String(s).toLowerCase().replace(/(^|[\s'])([a-zà-ù])/g, (m, a, b) => a + b.toUpperCase()); }
// Righe di testo → {store, date, total, items, somma}. Funzione pura (si prova senza PDF).
const SOLO_PREZZO = /^-?\d+[.,]\d{2}(\s+[A-Z])?$/, FINISCE_PREZZO = /\s-?\d+[.,]\d{2}(\s+[A-Z])?$/;
// Copiando da un lettore PDF il prezzo può finire su una riga a parte: lo si riunisce alla descrizione.
function unisciPrezzi(righe) {
  const out = [];
  righe.forEach(r => {
    const u = out[out.length - 1];
    if (SOLO_PREZZO.test(r) && u !== undefined && !FINISCE_PREZZO.test(u) && !SOLO_PREZZO.test(u)) out[out.length - 1] = u + " " + r;
    else out.push(r);
  });
  return out;
}
function leggiScontrinoRighe(righe) {
  righe = unisciPrezzi(righe.map(r => String(r).replace(/\s+/g, " ").trim()).filter(Boolean));
  const testo = righe.join("\n");
  let catena = /tigros/i.test(testo) ? "Tigros" : /coop/i.test(testo) ? "Coop" : "";
  const mc = righe.slice(0, 12).join(" ").toUpperCase().match(NOMI_CITTA);
  const store = (catena || (righe[0] || "").slice(0, 20)) + (mc ? " " + titolo(mc[1].replace(/^\d+\s*/, "").replace(/^.*\b(?:VIA|PIAZZA|CORSO|VIALE)\b.*,\s*/, "").trim()) : "");
  const md = testo.match(/(\d{2})\/(\d{2})\/(\d{4})/);
  const date = md ? md[3] + "-" + md[2] + "-" + md[1] : "";
  const mt = testo.match(/T[O0]TALE\s+COMPLESSIVO[^\d\n-]*(-?\d+[.,]\d{2})/i) || testo.match(/IMPORTO\s+PAGATO[^\d\n-]*(-?\d+[.,]\d{2})/i);
  const total = mt ? numIt(mt[1]) : null;
  const items = [];
  const conIntestazione = righe.some(r => /^DESCRIZIONE/i.test(r));
  let dentro = !conIntestazione, banco = false;
  for (const riga of righe) {
    if (!dentro) { if (/^DESCRIZIONE/i.test(riga)) dentro = true; continue; }
    if (/^(SUBTOTALE|ARTICOLI|T[O0]TALE)/i.test(riga)) break;
    if (/^Inizio sacc/i.test(riga)) { banco = true; continue; }
    if (/^Fine sacc/i.test(riga)) { banco = false; continue; }
    if (/^N\.\s*ART/i.test(riga)) continue;
    const m = riga.match(/^(.*?)\s+(-?\d+[.,]\d{2})(?:\s+[A-Z])?$/);
    if (!m) continue;
    const nome = m[1].replace(/^[.\s]+/, "").trim(), val = numIt(m[2]);
    const ultimo = items[items.length - 1];
    if ((val < 0 || /^(SCONTO|SC\.|PROMO|RIDUZ|OFFERTA)/i.test(nome)) && ultimo) {
      ultimo.price = round2(ultimo.price + val); ultimo.unitPrice = ultimo.price; continue;   // sconto: si toglie dalla riga sopra
    }
    const cat = classeDaNome(nome);
    items.push({code: "", name: nome, qty: 1, unit: "pc", unitPrice: val, price: val, cat, g: "",
      bio: /\bBIO\b/i.test(nome), size: "", _guess: cat === "other" && !banco});
  }
  const somma = round2(items.reduce((a, i) => a + i.price, 0));
  return {store, date, total, items, somma, nRighe: righe.length, conIntestazione};
}
// ---------- Collegamento alla pagina ----------
function inizioPdf() { $("aiStatus").className = "status"; $("aiStatus").textContent = t("pdf.reading"); }
async function caricaScontrinoPdf(file) {
  inizioPdf();
  try { await caricaScontrinoRighe(await righePdf(file)); } catch (e) { erroreScontrino(e); }
}
function erroreScontrino(e) {
  $("aiStatus").className = "status err";
  $("aiStatus").textContent = e && e.code === "pdfjs" ? t("pdf.nolib") : e && e.code === "empty" ? t("pdf.empty") + (e.n != null ? " " + t("pdf.diag", {n: e.n, h: e.head ? t("pdf.yes") : t("pdf.no")}) : "") : t("pdf.err");
}
async function caricaScontrinoRighe(righe) {
  const r = leggiScontrinoRighe(righe);
  if (!r.items.length) throw {code: "empty", n: r.nRighe, head: r.conIntestazione};
  const store = r.store;
  const mi = memoryIndex();
  let items = r.items.map(it => { const m = memFind(mi, store, it); if (m) { const x = fromMemory(it, m); x._mem = true; return x; } return it; });
  items.forEach(it => { if (it._mem === undefined) it._mem = false; });
  const nFav = applicaPreferiti(items);
  const todo = items.filter(i => i._guess);
  if (todo.length && sample) { try { await classifyItems(store, todo); } catch (e) {} }
  if (todo.length) applicaPreferiti(items);   // il modello può aver cambiato il nome generico: il preferito prevale
  items = items.map(it => { delete it._guess; delete it._mem; const m = withLib({store}, it); return {...m, _orig: {cat: m.cat, g: m.g || "", bio: !!m.bio, size: m.size || "", ct: co2Type(m)}}; });
  draft = {store, date: r.date, total: r.total, items};
  draftIsExample = false;
  const ok = r.total != null && Math.abs(r.somma - r.total) < 0.005;
  $("aiStatus").className = ok ? "status" : "status err";
  $("aiStatus").textContent = ok ? t("pdf.ok", {n: items.length, tot: eur(r.total)})
    : t("pdf.diff", {n: items.length, somma: eur(r.somma), tot: r.total == null ? "?" : eur(r.total)});
  renderAll();
  $("draftSec").scrollIntoView({behavior: "smooth", block: "start"});
}
function eUnPdf(f) { return f && (f.type === "application/pdf" || /\.pdf$/i.test(f.name)); }
function ricevutoFile(f) { $("aiStatus").className = "status"; $("aiStatus").textContent = t("pdf.got", {name: f.name}); }
$("photo").addEventListener("change", e => {
  const f = e.target.files && e.target.files[0];
  if (!eUnPdf(f)) return;
  photoFile = null; $("previewBox").hidden = true; $("readBtn").disabled = true;
  ricevutoFile(f); caricaScontrinoPdf(f); e.target.value = "";
});
function segnale(k) { $("aiStatus").className = "status"; $("aiStatus").textContent = t(k); }
$("pdfFile").addEventListener("click", () => segnale("pdf.waiting"));
$("pdfFile").addEventListener("cancel", () => segnale("pdf.nofile"));
["change", "input"].forEach(ev => $("pdfFile").addEventListener(ev, e => {
  const f = e.target.files && e.target.files[0];
  if (!f) return;
  ricevutoFile(f); caricaScontrinoPdf(f); e.target.value = "";
}));
// trascinare il PDF sulla scheda funziona anche quando il selettore di file è bloccato
["dragover", "drop"].forEach(ev => document.addEventListener(ev, e => {
  e.preventDefault();
  if (ev !== "drop") return;
  const f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
  if (eUnPdf(f)) { ricevutoFile(f); caricaScontrinoPdf(f); }
}));
$("pdfTextBtn").addEventListener("click", async () => {
  const righe = $("pdfText").value.split(/\r?\n/).map(x => x.replace(/\s+/g, " ").trim()).filter(Boolean);
  inizioPdf();
  try { await caricaScontrinoRighe(righe); } catch (e) { erroreScontrino(e); }
});
