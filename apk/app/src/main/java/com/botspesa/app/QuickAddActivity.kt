package com.botspesa.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken

/** Mini-finestra aperta dal widget: una casella, Invio aggiunge alla lista personale. */
class QuickAddActivity : AppCompatActivity() {

    private data class Dest(val gruppoId: Int, val topicId: Int, val label: String)

    private lateinit var input: EditText
    private lateinit var destView: TextView
    private lateinit var catView: TextView
    private lateinit var soloView: TextView
    private lateinit var prefs: android.content.SharedPreferences
    private var sending = false
    private var dest = Dest(0, 0, PERSONALE)
    private var cache: List<Dest> = emptyList()
    private var refreshing = false
    private val gson = Gson()
    private var soloPerMe = false
    private var categoria: ApiClient.CategoriaItem? = null
    private var catCache: MutableMap<String, List<ApiClient.CategoriaItem>> = mutableMapOf()
    private var userId = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
        userId = prefs.getInt("user_id", 0)
        if (userId == 0 || !prefs.contains("api_url")) {
            startActivity(Intent(this, MainActivity::class.java))
            finish()
            return
        }
        ApiClient.configure(
            url = prefs.getString("api_url", "") ?: "",
            tok = prefs.getString("api_token", "") ?: ""
        )

        setContentView(R.layout.activity_quick_add)
        window.setSoftInputMode(
            WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_VISIBLE or
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        )

        window.setLayout(
            (resources.displayMetrics.widthPixels * 0.96f).toInt(),
            WindowManager.LayoutParams.WRAP_CONTENT
        )
        input = findViewById(R.id.quick_add_input)
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND || actionId == EditorInfo.IME_ACTION_DONE) {
                invia()
                true
            } else false
        }
        destView = findViewById(R.id.quick_add_dest)
        dest = Dest(
            prefs.getInt(KEY_GRUPPO, 0),
            prefs.getInt(KEY_TOPIC, 0),
            prefs.getString(KEY_LABEL, PERSONALE) ?: PERSONALE
        )
        cache = leggiCache()
        mostraDest()
        destView.setOnClickListener { sceglieDestinazione() }
        catView = findViewById(R.id.quick_add_cat)
        soloView = findViewById(R.id.quick_add_solo)
        catView.setOnClickListener { sceglieCategoria() }
        soloView.setOnClickListener { impostaSolo(!soloPerMe) }
        catCache = leggiCatCache()
        // "*" iniziale (come in Telegram) = solo per me
        input.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(e: android.text.Editable?) {
                if (e != null && e.startsWith("*")) {
                    e.delete(0, 1)
                    impostaSolo(true)
                }
            }
        })
        aggiornaEffettiva()
        input.requestFocus()

        // aggiornamento elenco in parallelo alla digitazione
        aggiornaElenco(userId)
    }

    private fun effettiva(): Dest = if (soloPerMe) Dest(0, 0, PERSONALE) else dest

    private fun mostraDest() {
        destView.text = "📍 ${effettiva().label}  ▾"
        destView.alpha = if (soloPerMe) 0.45f else 1f
    }

    private fun impostaSolo(on: Boolean) {
        if (soloPerMe == on) return
        soloPerMe = on
        aggiornaEffettiva()
    }

    /** Destinazione effettiva cambiata: categoria torna a "Nessuna" e si ricarica l'elenco. */
    private fun aggiornaEffettiva() {
        soloView.isSelected = soloPerMe
        destView.isEnabled = !soloPerMe
        mostraDest()
        categoria = null
        mostraCat()
        aggiornaCategorie(effettiva())
    }

    private fun mostraCat() {
        catView.text = "🏷 ${categoria?.nome ?: "Nessuna categoria"}  ▾"
    }

    private fun chiaveCat(d: Dest) = "${d.gruppoId}_${d.topicId}"

    private fun leggiCatCache(): MutableMap<String, List<ApiClient.CategoriaItem>> = runCatching {
        gson.fromJson<MutableMap<String, List<ApiClient.CategoriaItem>>>(
            prefs.getString(KEY_CAT_CACHE, "{}"),
            object : TypeToken<MutableMap<String, List<ApiClient.CategoriaItem>>>() {}.type
        ) ?: mutableMapOf()
    }.getOrDefault(mutableMapOf())

    private fun aggiornaCategorie(d: Dest) {
        lifecycleScope.launch {
            val nuove = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getCategorie(d.gruppoId, d.topicId, userId) }.getOrNull()
            } ?: return@launch
            catCache[chiaveCat(d)] = nuove
            prefs.edit().putString(KEY_CAT_CACHE, gson.toJson(catCache)).apply()
        }
    }

    private fun sceglieCategoria() {
        val elenco = catCache[chiaveCat(effettiva())].orEmpty()
        val voci = (listOf("Nessuna categoria") + elenco.map { it.nome }).toTypedArray()
        val corrente = categoria?.let { c -> elenco.indexOfFirst { it.id == c.id } + 1 } ?: 0
        AlertDialog.Builder(this)
            .setTitle("Categoria")
            .setSingleChoiceItems(voci, corrente) { d, which ->
                categoria = if (which == 0) null else elenco[which - 1]
                mostraCat()
                d.dismiss()
            }
            .setOnDismissListener { input.requestFocus() }
            .show()
    }

    private fun leggiCache(): List<Dest> = runCatching {
        gson.fromJson<List<Dest>>(
            prefs.getString(KEY_CACHE, "[]"),
            object : TypeToken<List<Dest>>() {}.type
        ) ?: emptyList()
    }.getOrDefault(emptyList())

    private fun aggiornaElenco(userId: Int) {
        refreshing = true
        lifecycleScope.launch {
            val nuovo = withContext(Dispatchers.IO) {
                runCatching {
                    buildList {
                        add(Dest(0, 0, PERSONALE))
                        ApiClient.getGruppiTyped(userId).filter { it.id != 0 }.forEach { g ->
                            val topics = ApiClient.getTopics(g.id)
                            if (topics.isEmpty()) add(Dest(g.id, 0, "${g.nome}: Principale"))
                            else topics.forEach { t -> add(Dest(g.id, t.topicId, "${g.nome}: ${t.nome}")) }
                        }
                    }
                }.getOrNull()
            }
            refreshing = false
            if (nuovo != null) {
                cache = nuovo
                prefs.edit().putString(KEY_CACHE, gson.toJson(nuovo)).apply()
                // la destinazione salvata potrebbe essere stata rinominata/rimossa
                nuovo.firstOrNull { it.gruppoId == dest.gruppoId && it.topicId == dest.topicId }
                    ?.let { if (it.label != dest.label) { dest = it; salvaDest(); mostraDest() } }
            }
        }
    }

    private fun salvaDest() {
        prefs.edit()
            .putInt(KEY_GRUPPO, dest.gruppoId)
            .putInt(KEY_TOPIC, dest.topicId)
            .putString(KEY_LABEL, dest.label)
            .apply()
        val mgr = android.appwidget.AppWidgetManager.getInstance(this)
        val ids = mgr.getAppWidgetIds(android.content.ComponentName(this, QuickAddWidget::class.java))
        if (ids.isNotEmpty()) QuickAddWidget().onUpdate(this, mgr, ids)
    }

    private fun sceglieDestinazione() {
        val elenco = cache.ifEmpty { listOf(Dest(0, 0, PERSONALE)) }
        val corrente = elenco.indexOfFirst { it.gruppoId == dest.gruppoId && it.topicId == dest.topicId }
        AlertDialog.Builder(this)
            .setTitle(if (refreshing && cache.isEmpty()) "Caricamento…" else "Destinazione")
            .setSingleChoiceItems(elenco.map { it.label }.toTypedArray(), corrente) { d, which ->
                dest = elenco[which]
                salvaDest()
                aggiornaEffettiva()
                d.dismiss()
            }
            .setOnDismissListener { input.requestFocus() }
            .show()
    }

    private fun invia() {
        val testo = input.text.toString().trim()
        if (testo.isEmpty() || sending) return
        sending = true
        input.isEnabled = false
        val eff = effettiva()
        lifecycleScope.launch {
            val errore = withContext(Dispatchers.IO) {
                try {
                    ApiClient.addItem(
                        gruppoId = eff.gruppoId, topicId = eff.topicId, nome = testo,
                        userId = userId, categoriaId = categoria?.id
                    )
                    null
                } catch (e: Exception) {
                    e.message ?: "errore"
                }
            }
            if (errore == null) {
                Toast.makeText(this@QuickAddActivity, "Aggiunto ✓ ${eff.label}", Toast.LENGTH_SHORT).show()
                finish()
            } else {
                // il testo resta nella casella: nulla va perso
                Toast.makeText(this@QuickAddActivity, errore, Toast.LENGTH_LONG).show()
                sending = false
                input.isEnabled = true
                input.requestFocus()
            }
        }
    }

    private companion object {
        const val PERSONALE = "Lista Personale"
        const val KEY_GRUPPO = "widget_dest_gruppo"
        const val KEY_TOPIC = "widget_dest_topic"
        const val KEY_LABEL = "widget_dest_label"
        const val KEY_CACHE = "widget_dest_cache"
        const val KEY_CAT_CACHE = "widget_cat_cache"
    }
}
