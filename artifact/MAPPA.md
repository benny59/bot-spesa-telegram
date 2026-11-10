# Artifact "Basket Index": mappa dei blocchi

Origine: `basket-index.html` (3571 righe, **non modificato**, resta come riferimento e sorgente delle frasi originali in inglese).
Versione spezzata: cartella `app/` (stesso comportamento, verificato: DOM identico a quello dell'originale in Chrome headless, nessun errore in console).

```
app/
  index.html        struttura della pagina (righe 363-643 dell'originale) + elenco degli script
  css/stile.css     stili (righe 6-360)
  js/NN-nome.js     27+1 blocchi, caricati nell'ordine dei numeri (script classici, stesso ambito globale)
```

**Regola dei file JS**: sono script classici in sequenza, non moduli. Le variabili `let/const` e le funzioni di un file sono visibili ai successivi. Una funzione **non** si può chiamare al caricamento prima che il suo file sia stato eseguito (nell'originale le funzioni erano "sollevate" nello stesso blocco). Per questo `00-utilita.js` è il primo. Controllo rapido dopo ogni modifica: aprire `app/index.html` e leggere la console.

## Blocchi

Stato: **N** = nucleo della prima tappa, **D** = dipendenza tecnica (va caricato, non si vede), **E** = estensione (scheda nascosta nella prima tappa), **X** = da eliminare/sostituire.

| File | Righe orig. | Contenuto | Stato | Da adattare all'Italia |
|---|---|---|---|---|
| 00-utilita | 738-748 | `$`, `eur`, `pct`, `esc`, date, `cls` | N | formato `de-DE` → `it-IT` |
| 01-catalogo-tassi | 647-699 | tassi ufficiali (Destatis/Eurostat), 15 classi COICOP | N | **ISTAT**, nomi classi |
| 02-esempio | 700-728 | scontrino ALDI di esempio | X | sostituire con esempio Coop/Tigros o togliere |
| 03-stato | 729-737 | variabili di stato (scontrini, bozza, db, sample) | N | |
| 04-paniere-tassi | 750-772 | inflazione "sul tuo paniere" | N | |
| 05-igiene-scontrini | 773-827 | righe alimentari, catena, duplicati, formati, `matchOf` | N | righe **a peso** senza kg; regex banco (`sacc`, `banco`) |
| 06-indice-prezzi | 828-881 | chiave articolo, indice a catena, ritmo ufficiale | N | chiave = catena + descrizione (senza codice articolo) |
| 07-prezzi-ui | 882-1080 | grafico e dettaglio dell'indice, tabella mensile | N | testi |
| 08-confronto-negozi-ui | 1081-1142 | stesso prodotto in negozi diversi | N | solo stessa descrizione per catena |
| 09-nutrizione-dati | 1143-1244 | `NUT`, tipi climatici CO₂ e regole per nome | D (`CO2T`) / E | regole in italiano |
| 10-nutrizione-punteggi | 1245-1309 | longevità, `MIC`, Nutri-Score | E | |
| 11-famiglia-radar | 1310-1420 | famiglia (adulti/bambini), radar settimanale | D (`household`) / E | |
| 12-prezzo-nutrizione | 1421-1563 | NRF, scatter prezzo × nutrienti | E | |
| 13-clima-longevita | 1564-1704 | clima, longevità, grassi, tooltip scatter | E | |
| 14-nutrizione-core | 1705-1891 | `nsOf`, peso per unità, `withLib`, `renderNutrition` | D (`withLib`, `library`) / E | |
| 15-etichette-foto | 1892-2072 | etichetta nutrizionale da foto, stime | E | |
| 16-riepilogo-render | 2073-2192 | riepilogo tassi, bozza, ripetuti, storico, `renderAll` | N | |
| 17-bozza-salvataggio | 2193-2281 | modifica bozza, salva, tassi | N | |
| 18-lettura-scontrino | 2282-2379 | foto → righe con modello (prompt e classi) | N | **qui entra il parser PDF Coop/Tigros**; prompt in italiano |
| 19-memoria-prodotti | 2380-2561 | memoria per prodotto, regole, classificazione | N | chiave senza codice |
| 20-guscio-colpo-docchio | 2562-2628 | schede (`VIEWS`), tile "a colpo d'occhio" | N | |
| 21-dispensa | 2629-2744 | cosa c'è in casa, scadenze tipiche | E | regex in italiano |
| 22-ricette | 2745-2960 | 3 ricette dai prodotti in casa | E | stile italiano |
| 23-solver-lp | 2961-3023 | simplex | E | nessuno |
| 24-settimana-modello | 3024-3224 | modello del piano settimana, allenamenti | E | allenamenti disattivi |
| 25-settimana-ui | 3225-3437 | UI del piano, menu | E | |
| 26-pasti-migliori | 3438-3516 | pasti cucinati, "più nutrienti" | E | |
| 27-avvio | 3517-3569 | avvio, capacità `sample`/`db`/`user`, snapshot db | N | |

Nota sulle dipendenze: il nucleo usa `withLib`/`library` (14) e `CO2T` (09), quindi **tutti i file restano caricati**; la prima tappa nasconde le schede *Nutrizione* e *Ricette* (cambia `VIEWS` in `20` e i tab in `index.html`).

## Lingua (italiano + inglese, come il tedesco in Android)

Modello da seguire: `apk/app/src/main/assets/locales.json`, chiavi tipo `admin.title` con una sezione per lingua.

- `app/i18n/locali.js` → `const LOCALI = { it: {...}, en: {...} }` (un `.js` e non un `.json`: nessun `fetch`, nessun problema di caricamento nell'artifact).
- **`en` = frasi originali, copiate alla lettera** dall'`basket-index.html`; `it` = traduzione. Se una chiave non c'è in `it`, si mostra `en`.
- `app/js/00-i18n.js` (**fatto**, con pulsante IT/EN in alto, lingua in `localStorage("bi-lang")`): `t("chiave", {vars})`, lingua da `localStorage("bi-lang")`, predefinita `it`; testo statico dell'HTML con `data-i18n="chiave"` applicato all'avvio e al cambio lingua.
- Migrazione **un blocco per volta**: nel blocco, ogni frase inglese nei template diventa `${t("blocco.chiave")}`, e la stessa frase va in `en`. Si comincia dai blocchi del nucleo (07, 08, 16, 17, 18, 20) e dall'HTML.
- Frasi con numeri/plurali: chiavi con segnaposto (`{n}`), un caso singolare e uno plurale dove serve.
- I **prompt al modello** (18, 19, 15, 22, 25) non sono testo utente: tenere la versione in italiano per scontrini italiani, l'originale inglese resta in `en`.

## Pubblicazione

L'artifact supporta file collegati: `index.html` come pagina e `css/`, `js/`, `i18n/` come `files`. Le capacità dichiarate dall'altro progetto: `{"sample":{"images":true},"db":{"rules":[{"path":"household","read":"admin","write":"admin"}]},"user":{}}`. Privato per impostazione predefinita.

## Ponte "Aggiungi alla lista" (più avanti)

Blocco isolato nuovo (`28-ponte-spesa.js`): una funzione che trasforma voci scelte in testo `+voce` (copia/condividi). Attivabile per utente con un interruttore; se spento, nessun pulsante compare. Vedi Parte C di `../FUNZIONI_E_PIATTAFORME.md`.

## Stato i18n (2026-11-09)

- Fatto: infrastruttura + testo statico dell'HTML del nucleo (intestazione, schede, Prezzi, Scontrini): 29 chiavi, `en` alla lettera.
- Da fare: testi generati nei blocchi JS (07, 08, 16, 17, 18, 19, 20, 27), poi le schede Nutrizione/Ricette quando servono.
- Comandi: aggiungere frasi con `data-i18n="chiave"` (HTML) o `t("chiave",{n})` (JS) e la coppia en/it in `locali.js`.
