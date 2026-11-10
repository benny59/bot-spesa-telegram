"use strict";
// ---------- State ----------
let receipts = [];
let draft = null; // prima: clone(EXAMPLE), l'esempio ALDI non parte più
let draftIsExample = false;
let loaded = false;
let selected = null; // receipt id selected on the chart
let editingId = null; // saved receipt being corrected
let db = null, uid = null, COL = null, sample = null, photoFile = null, ctl = null;

let histAll = false;                 // elenco scontrini: solo gli ultimi 3 finché non si preme "Mostra tutti"
let ponteSpunte = new Set();         // voci spuntate per "Aggiungi alla lista" (scontrino o memoria prodotti)
let favs = [];                       // preferiti di Spesa importati: [{d: nome, e: codice a barre}]

let tuttiDocs = [];   // copia dei documenti del database (id + corpo) per l'esportazione
