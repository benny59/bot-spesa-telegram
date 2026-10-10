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
    private lateinit var prefs: android.content.SharedPreferences
    private var sending = false
    private var dest = Dest(0, 0, PERSONALE)
    private var cache: List<Dest> = emptyList()
    private var refreshing = false
    private val gson = Gson()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        prefs = getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
        val userId = prefs.getInt("user_id", 0)
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
                invia(userId)
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
        input.requestFocus()

        // aggiornamento elenco in parallelo alla digitazione
        aggiornaElenco(userId)
    }

    private fun mostraDest() {
        destView.text = "📍 ${dest.label}  ▾"
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
                mostraDest()
                d.dismiss()
            }
            .setOnDismissListener { input.requestFocus() }
            .show()
    }

    private fun invia(userId: Int) {
        val testo = input.text.toString().trim()
        if (testo.isEmpty() || sending) return
        sending = true
        input.isEnabled = false
        lifecycleScope.launch {
            val errore = withContext(Dispatchers.IO) {
                try {
                    ApiClient.addItem(gruppoId = dest.gruppoId, topicId = dest.topicId, nome = testo, userId = userId)
                    null
                } catch (e: Exception) {
                    e.message ?: "errore"
                }
            }
            if (errore == null) {
                Toast.makeText(this@QuickAddActivity, "Aggiunto ✓ ${dest.label}", Toast.LENGTH_SHORT).show()
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
    }
}
