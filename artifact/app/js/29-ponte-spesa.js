"use strict";
// ---------- Ponte "Aggiungi alla lista" ----------
// L'artifact non può chiamare il nostro server (blocco di rete): prepara un link alla PWA
// (.../app/?aggiungi=voce1,voce2) e un testo "+voce" da incollare in Telegram. Conferma sempre l'utente.
const PWA_PREDEFINITA = "https://bennyspesa.duckdns.org:4443/app/";
let ponteSrc = "";
function vociPonte() { return $("bridgeItems").value.split(",").map(s => s.trim()).filter(Boolean); }
function fontiPonte() {
  const f = [];
  if (typeof draft !== "undefined" && draft && draft.items) f.push({id: "draft", label: t("bridge.draft"), r: draft});
  cleanReceipts().slice().sort((a, b) => String(b.date).localeCompare(String(a.date))).forEach(r =>
    f.push({id: "r:" + (r.id || r.date + r.store), label: r.store + " · " + r.date, r}));
  return f;
}
function renderPonte() {
  const f = fontiPonte(), sel = $("bridgeSrc");
  sel.innerHTML = f.map(x => `<option value="${esc(x.id)}">${esc(x.label)}</option>`).join("");
  sel.hidden = !f.length;
  if (!f.some(x => x.id === ponteSrc)) ponteSrc = f.length ? f[0].id : "";
  sel.value = ponteSrc;
  const cur = f.find(x => x.id === ponteSrc);
  const righe = cur ? cur.r.items.filter(it => it.cat !== EXCLUDED && nomeVoce(it)) : [];
  $("bridgeList").innerHTML = righe.map((it, i) => {
    const n = nomeVoce(it);
    return `<label class="chk" style="display:flex;gap:8px;align-items:center;padding:3px 0"><input type="checkbox" data-n="${esc(n)}"${ponteSpunte.has(n) ? " checked" : ""}> <span>${esc(n)}</span> ${favChip(it)} <span class="status">${eur(it.price)}</span></label>`;
  }).join("") || `<p class="status">${esc(t("bridge.none"))}</p>`;
}
function aggiornaPonte() {
  const v = vociPonte();
  const base = $("bridgeUrl").value.trim() || PWA_PREDEFINITA;
  try { localStorage.setItem("bi-pwa", base); } catch (e) {}
  $("bridgeLink").href = v.length ? base + (base.indexOf("?") < 0 ? "?" : "&") + "aggiungi=" + encodeURIComponent(v.join(",")) : "#";
  $("bridgeLink").style.opacity = v.length ? "" : "0.5";
  $("bridgeCopy").disabled = !v.length;
  // barra sotto "Memoria dei prodotti"
  $("memBar").hidden = !v.length;
  $("memBarN").textContent = t("mem.n", {n: v.length});
  $("memBarLink").href = $("bridgeLink").href;
}
// Spunta/toglie una voce da qualunque elenco (scontrino o memoria); il campo e i link si aggiornano.
function togglaVoce(nome, on) {
  on ? ponteSpunte.add(nome) : ponteSpunte.delete(nome);
  $("bridgeItems").value = [...ponteSpunte].join(", ");
  aggiornaPonte();
  renderPonte();
}
(function () {
  let base = PWA_PREDEFINITA; try { base = localStorage.getItem("bi-pwa") || base; } catch (e) {}
  $("bridgeUrl").value = base;
  $("bridgeItems").addEventListener("input", aggiornaPonte);
  $("bridgeUrl").addEventListener("change", aggiornaPonte);
  $("bridgeSrc").addEventListener("change", e => { ponteSrc = e.target.value; ponteSpunte.clear(); $("bridgeItems").value = ""; renderPonte(); aggiornaPonte(); });
  $("bridgeList").addEventListener("change", e => {
    const c = e.target.closest("input[data-n]"); if (!c) return;
    togglaVoce(c.dataset.n, c.checked);
    renderMemory();
  });
  $("bridgeItems").addEventListener("input", () => { ponteSpunte = new Set(vociPonte()); });
  $("memBarLink").addEventListener("click", e => { if (!vociPonte().length) e.preventDefault(); });
  $("memBarCopy").addEventListener("click", () => $("bridgeCopy").click());
  $("memBarClear").addEventListener("click", () => { ponteSpunte.clear(); $("bridgeItems").value = ""; aggiornaPonte(); renderPonte(); renderMemory(); });
  $("bridgeLink").addEventListener("click", e => { if (!vociPonte().length) e.preventDefault(); });
  $("bridgeCopy").addEventListener("click", async () => {
    const testo = vociPonte().map(x => "+" + x).join("\n");
    try { await navigator.clipboard.writeText(testo); $("bridgeStatus").textContent = t("bridge.copied"); }
    catch (e) { $("bridgeStatus").textContent = t("bridge.nocopy"); }
  });
  const ra = renderAll;
  renderAll = function () { try { ra(); } finally { try { renderPonte(); } catch (e) { console.error(e); } } };
  renderPonte(); aggiornaPonte();
})();
