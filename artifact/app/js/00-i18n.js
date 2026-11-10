"use strict";
// Traduzioni: LOCALI = {it:{chiave:testo}, en:{...}} (i18n/locali.js). en = frasi originali.
// Uso: t("chiave", {n:3}) con segnaposto {n}; testo statico: data-i18n="chiave".
// Attributi: data-i18n-aria (aria-label), data-i18n-ph (placeholder), data-i18n-title (title).
let LANG = "it";
try { const s = localStorage.getItem("bi-lang"); if (s === "it" || s === "en") LANG = s; } catch (e) {}
function t(key, vars) {
  let s = (LOCALI[LANG] && LOCALI[LANG][key]) ?? (LOCALI.en && LOCALI.en[key]) ?? key;
  if (vars) s = s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k] : m));
  return s;
}
function applyI18n(root) {
  (root || document).querySelectorAll("[data-i18n]").forEach(el => { el.textContent = t(el.dataset.i18n); });
  [["i18nAria", "aria-label"], ["i18nPh", "placeholder"], ["i18nTitle", "title"]].forEach(([d, a]) =>
    (root || document).querySelectorAll("[data-i18n-" + d.slice(4).toLowerCase() + "]").forEach(el => el.setAttribute(a, t(el.getAttribute("data-i18n-" + d.slice(4).toLowerCase())))));
  document.documentElement.lang = LANG;
  const b = document.getElementById("langBtn"); if (b) b.textContent = LANG === "it" ? "EN" : "IT";
}
function setLang(l) {
  LANG = l; try { localStorage.setItem("bi-lang", l); } catch (e) {}
  applyI18n();
  if (typeof renderAll === "function") { try { renderAll(); } catch (e) {} }
}
document.addEventListener("DOMContentLoaded", () => {
  applyI18n();
  const b = document.getElementById("langBtn");
  if (b) b.addEventListener("click", () => setLang(LANG === "it" ? "en" : "it"));
});
