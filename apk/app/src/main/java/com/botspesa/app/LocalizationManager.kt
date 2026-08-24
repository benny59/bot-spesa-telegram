package com.botspesa.app

import android.content.Context
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.InputStreamReader
import java.util.Locale

object LocalizationManager {
    private const val PREFS_NAME = "botspesa_prefs"
    private const val KEY_LANGUAGE = "app_language"
    private const val ASSET_TRANSLATIONS = "locales.json"

    data class LanguageOption(
        val code: String,
        val label: String,
    )

    fun supportedLanguages(): List<LanguageOption> = listOf(
        LanguageOption("it", "Italiano"),
        LanguageOption("de", "Deutsch"),
    )

    fun normalizeLanguageCode(languageCode: String?): String {
        val raw = languageCode?.trim()?.ifEmpty { null } ?: return "it"
        val normalized = raw.replace('_', '-').substringBefore('-').lowercase(Locale.ROOT)
        return if (supportedLanguages().any { it.code == normalized }) normalized else "it"
    }

    fun currentLanguageCode(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val stored = prefs.getString(KEY_LANGUAGE, null)
        return normalizeLanguageCode(stored ?: Locale.getDefault().language)
    }

    fun applyLanguage(context: Context, languageCode: String) {
        val normalized = normalizeLanguageCode(languageCode)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putString(KEY_LANGUAGE, normalized).apply()
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(normalized))
    }

    fun applyAppLocale(context: Context) {
        val lang = currentLanguageCode(context)
        AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags(lang))
    }

    fun translationForKey(context: Context, key: String, fallback: String): String {
        val locale = currentLanguageCode(context)
        val translations = loadTranslations(context) ?: return fallback
        val langMap = translations[locale] as? Map<*, *> ?: return fallback
        return langMap[key]?.toString() ?: fallback
    }

    fun localizedCategoryName(context: Context, rawCategoryName: String?): String {
        val value = rawCategoryName?.trim().orEmpty()
        if (value.isEmpty()) return value

        if (currentLanguageCode(context) != "de") return value

        return when (value.lowercase(Locale.ROOT)) {
            "verdura" -> "Gemüse"
            "frutta" -> "Obst"
            "latticini" -> "Milchprodukte"
            "carne" -> "Fleisch"
            "pesce" -> "Fisch"
            "pane" -> "Brot"
            "snack" -> "Snacks"
            "bevande" -> "Getränke"
            "casa" -> "Haushalt"
            "igiene" -> "Hygiene"
            "gastronomia" -> "Gastronomie"
            "altro" -> "Sonstiges"
            else -> value
        }
    }

    private fun loadTranslations(context: Context): Map<String, Map<String, String>>? {
        return runCatching {
            val input = context.assets.open(ASSET_TRANSLATIONS)
            val type = object : TypeToken<Map<String, Map<String, String>>>() {}.type
            Gson().fromJson<Map<String, Map<String, String>>>(InputStreamReader(input), type)
        }.getOrNull()
    }
}
