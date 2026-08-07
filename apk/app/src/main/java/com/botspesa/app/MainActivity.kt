package com.botspesa.app

import android.app.AlertDialog
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.widget.EditText
import android.widget.PopupMenu
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.ActionBarDrawerToggle
import androidx.appcompat.app.AppCompatActivity
import androidx.appcompat.widget.Toolbar
import androidx.core.content.FileProvider
import androidx.drawerlayout.widget.DrawerLayout
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.floatingactionbutton.FloatingActionButton
import com.google.android.material.navigation.NavigationView
import com.google.android.material.snackbar.Snackbar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: SpesaAdapter
    private lateinit var drawerLayout: DrawerLayout
    private lateinit var tvGruppo: TextView
    private lateinit var tvTopic: TextView
    private val items = mutableListOf<SpesaItem>()
    private var pendingFotoItemId = 0
    private var cameraImageUri: Uri? = null

    private val pickImageLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let { uploadFotoFromUri(it, pendingFotoItemId) }
    }
    private val takePhotoLauncher = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok) cameraImageUri?.let { uploadFotoFromUri(it, pendingFotoItemId) }
    }
    private val requestCameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) launchCamera() else Toast.makeText(this, "Permesso fotocamera negato", Toast.LENGTH_SHORT).show()
    }

    private val gruppoId get() = prefs().getInt("gruppo_id", 1)
    private val topicId  get() = prefs().getInt("topic_id", 0)
    private val userId   get() = prefs().getInt("user_id", 0)
    private val firstName get() = prefs().getString("user_first_name", "") ?: ""
    private val lastName  get() = prefs().getString("user_last_name", "") ?: ""

    private fun aggiornaNomeUtente() {
        val navView = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navView)
        val header = navView.getHeaderView(0)
        val tvUser = header.findViewById<TextView>(R.id.tvUserName)
        val nome = listOf(firstName, lastName).filter { it.isNotEmpty() }.joinToString(" ")
        tvUser.text = if (nome.isNotEmpty()) "👤 $nome" else "(non collegato)"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val prefs = prefs()
        ApiClient.configure(
            url = prefs.getString("api_url", "http://10.0.2.2:4567") ?: "http://10.0.2.2:4567",
            tok = prefs.getString("api_token", "") ?: ""
        )

        adapter = SpesaAdapter(
            items      = items,
            onToggle   = ::toggleItem,
            onFoto     = ::apriFoto,
            onLongPress = { item, anchor -> mostraMenuContestuale(item, anchor) }
        )

        drawerLayout = findViewById(R.id.drawerLayout)
        val toolbar = findViewById<Toolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayShowTitleEnabled(false)
        val selectorView = layoutInflater.inflate(R.layout.toolbar_group_topic, toolbar, false)
        tvGruppo = selectorView.findViewById(R.id.tvGruppoSelector)
        tvTopic  = selectorView.findViewById(R.id.tvTopicSelector)
        tvGruppo.setOnClickListener { mostraDialogCambioGruppo() }
        tvTopic.setOnClickListener  { mostraDialogCambioTopic() }
        toolbar.addView(selectorView)
        val toggle = ActionBarDrawerToggle(
            this, drawerLayout, toolbar,
            R.string.open_drawer, R.string.close_drawer
        )
        drawerLayout.addDrawerListener(toggle)
        toggle.syncState()

        findViewById<NavigationView>(R.id.navView).setNavigationItemSelectedListener { item ->
            drawerLayout.closeDrawers()
            when (item.itemId) {
                R.id.nav_cambia_gruppo     -> mostraDialogCambioGruppo()
                R.id.nav_collega_telegram  -> mostraDialogCollegaTelegram()
                R.id.nav_config_rete       -> mostraDialogConfigRete()
                R.id.nav_colori_gruppi     -> mostraDialogColoriTopic()
            }
            true
        }

        recyclerView = findViewById(R.id.recyclerView)
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter
        ItemTouchHelper(swipeCallback).attachToRecyclerView(recyclerView)

        findViewById<FloatingActionButton>(R.id.fab).setOnClickListener {
            mostraDialogAggiungi()
        }

        aggiornaLista()
        caricaInfoGruppo()
        aggiornaNomeUtente()
        if (prefs().getInt("user_id", 0) == 0) {
            mostraDialogCollegaTelegram(primoAvvio = true)
        }

        // Polling: aggiorna la lista ogni 5s quando l'app è in foreground
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                while (true) {
                    delay(5_000)
                    aggiornaLista()
                }
            }
        }
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menuInflater.inflate(R.menu.toolbar_menu, menu)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_scopetta -> { mostraScopettaConferma(); true }
            R.id.action_carte    -> { CarteSheet.newInstance(gruppoId).show(supportFragmentManager, "carte"); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun mostraScopettaConferma() {
        val comprati = items.count { it.isBought }
        if (comprati == 0) {
            Toast.makeText(this, "Nessun articolo comprato", Toast.LENGTH_SHORT).show()
            return
        }
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.scopetta))
            .setMessage("Rimuovere $comprati articol${if (comprati == 1) "o comprato" else "i comprati"}?")
            .setPositiveButton("Rimuovi") { _, _ -> eseguiScopetta() }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun eseguiScopetta() {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { ApiClient.eseguiScopetta(gruppoId, topicId, userId) }.getOrDefault(false)
            }
            if (ok) aggiornaLista()
            else Toast.makeText(this@MainActivity, "Errore scopetta", Toast.LENGTH_SHORT).show()
        }
    }

    // Colori toolbar per topic: chiave = substring del nome topic (lowercase)
    private val topicColors = mapOf(
        "giovi"   to R.color.topic_verde,
        "imperia" to R.color.topic_giallo,
        "tutti"   to R.color.topic_arancio
    )

    // Palette predefinita per il picker colori topic
    private val colorPalette = listOf(
        android.graphics.Color.parseColor("#1976D2") to "Blu",
        android.graphics.Color.parseColor("#2E7D32") to "Verde",
        android.graphics.Color.parseColor("#00695C") to "Teal",
        android.graphics.Color.parseColor("#E65100") to "Arancio",
        android.graphics.Color.parseColor("#C62828") to "Rosso",
        android.graphics.Color.parseColor("#6A1B9A") to "Viola",
        android.graphics.Color.parseColor("#283593") to "Indaco",
        android.graphics.Color.parseColor("#4E342E") to "Marrone"
    )

    private fun topicColorDefault(nome: String): Int {
        val lc = nome.lowercase()
        val res = topicColors.entries.firstOrNull { lc.contains(it.key) }?.value ?: R.color.colorPrimary
        return getColor(res)
    }

    private fun applicaColoreToolbar(gruppoId: Int, topicNome: String) {
        val color = if (gruppoId == 0) {
            android.graphics.Color.parseColor("#455A64") // Lista Personale: grigio-blu
        } else {
            val p = prefs()
            val colorKey = "topic_color_$topicId"
            if (p.contains(colorKey)) p.getInt(colorKey, 0)
            else topicColorDefault(topicNome)
        }
        findViewById<androidx.appcompat.widget.Toolbar>(R.id.toolbar).setBackgroundColor(color)
        window.statusBarColor = color
    }

    // Swipe destra = toggle comprato
    private val swipeCallback = object : ItemTouchHelper.SimpleCallback(
        0, ItemTouchHelper.RIGHT
    ) {
        override fun onMove(rv: RecyclerView, vh: RecyclerView.ViewHolder, t: RecyclerView.ViewHolder) = false

        override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            val pos  = viewHolder.adapterPosition
            val item = items[pos]
            adapter.notifyItemChanged(pos)
            toggleItem(item)
        }
    }

    private fun mostraDialogImpostazioni() = mostraDialogConfigRete()

    private fun mostraDialogCollegaTelegram(primoAvvio: Boolean = false) {
        val dp = resources.displayMetrics.density
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding((24 * dp).toInt(), (16 * dp).toInt(), (24 * dp).toInt(), 8)
        }
        android.widget.TextView(this).apply {
            text = "1. Apri Telegram e scrivi al bot:\n    /collegaapp\n\n2. Il bot risponderà con un PIN a 6 cifre.\n\n3. Inseriscilo qui sotto:"
            setPadding(0, 0, 0, (12 * dp).toInt())
        }.also { layout.addView(it) }
        val etPin = EditText(this).apply {
            hint = "PIN a 6 cifre"
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            maxLines = 1
        }
        layout.addView(etPin)
        val dlg = AlertDialog.Builder(this)
            .setTitle("Collega account Telegram")
            .setView(layout)
            .setPositiveButton("Collega", null)
            .also { if (!primoAvvio) it.setNegativeButton("Annulla", null) }
            .create()
        dlg.setOnShowListener {
            dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val pin = etPin.text.toString().trim()
                if (pin.length != 6) {
                    etPin.error = "Inserisci 6 cifre"
                    return@setOnClickListener
                }
                dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                lifecycleScope.launch {
                    val result = withContext(Dispatchers.IO) {
                        runCatching { ApiClient.collegaPin(pin) }
                    }
                    dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                    result.onSuccess { r ->
                        if (r != null) {
                            prefs().edit().putInt("user_id", r.userId).apply()
                            Toast.makeText(this@MainActivity, "\u2713 Benvenuto, ${r.firstName}!", Toast.LENGTH_LONG).show()
                            dlg.dismiss()
                        } else {
                            etPin.error = "PIN non valido o scaduto"
                        }
                    }.onFailure { e ->
                        etPin.error = e.message ?: "Errore di rete"
                    }
                }
            }
        }
        dlg.show()
    }

    private fun mostraDialogConfigRete() {
        val p = prefs()
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(48, 16, 48, 8)
        }
        val etUrl = EditText(this).apply {
            hint = "http://IP:4568"
            setText(p.getString("api_url", "http://10.0.2.2:4567"))
            inputType = android.text.InputType.TYPE_TEXT_VARIATION_URI
        }
        val etToken = EditText(this).apply {
            hint = "Token (lascia vuoto se non richiesto)"
            setText(p.getString("api_token", ""))
        }
        android.widget.TextView(this).apply { text = "URL server" }.also { layout.addView(it) }
        layout.addView(etUrl)
        android.widget.TextView(this).apply {
            text = "Token"
            setPadding(0, 16, 0, 0)
        }.also { layout.addView(it) }
        layout.addView(etToken)
        AlertDialog.Builder(this)
            .setTitle(getString(R.string.nav_config_rete))
            .setView(layout)
            .setPositiveButton("Salva") { _, _ ->
                val url   = etUrl.text.toString().trimEnd('/')
                val token = etToken.text.toString().trim()
                p.edit().putString("api_url", url).putString("api_token", token).apply()
                ApiClient.configure(url = url, tok = token)
                aggiornaLista()
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun mostraDialogColoriTopic() {
        lifecycleScope.launch {
            val topics = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getTopics(gruppoId) }.getOrDefault(emptyList())
            }
            if (topics.isEmpty()) return@launch
            val p = prefs()
            val dp = resources.displayMetrics.density
            val scroll = android.widget.ScrollView(this@MainActivity)
            val layout = android.widget.LinearLayout(this@MainActivity).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                setPadding((16 * dp).toInt(), (8 * dp).toInt(), (16 * dp).toInt(), (8 * dp).toInt())
            }
            scroll.addView(layout)
            topics.forEach { topic ->
                val colorKey = "topic_color_${topic.topicId}"
                val row = android.widget.LinearLayout(this@MainActivity).apply {
                    orientation = android.widget.LinearLayout.HORIZONTAL
                    gravity = android.view.Gravity.CENTER_VERTICAL
                    setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
                }
                val sz = (32 * dp).toInt()
                val dot = android.view.View(this@MainActivity).apply {
                    layoutParams = android.widget.LinearLayout.LayoutParams(sz, sz).also {
                        it.marginEnd = (16 * dp).toInt()
                    }
                    background = android.graphics.drawable.GradientDrawable().apply {
                        shape = android.graphics.drawable.GradientDrawable.OVAL
                        setColor(p.getInt(colorKey, topicColorDefault(topic.nome)))
                    }
                }
                val tvNome = android.widget.TextView(this@MainActivity).apply {
                    text = topic.nome
                    textSize = 16f
                    layoutParams = android.widget.LinearLayout.LayoutParams(
                        0, android.widget.LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                }
                val btnCambia = android.widget.Button(this@MainActivity).apply {
                    text = "Cambia"
                    setOnClickListener {
                        val nomi = colorPalette.map { it.second }.toTypedArray()
                        AlertDialog.Builder(this@MainActivity)
                            .setTitle("Colore per ${topic.nome}")
                            .setItems(nomi) { _, idx ->
                                val newColor = colorPalette[idx].first
                                p.edit().putInt(colorKey, newColor).apply()
                                (dot.background as android.graphics.drawable.GradientDrawable).setColor(newColor)
                                if (topicId == topic.topicId) applicaColoreToolbar(gruppoId, topic.nome)
                            }
                            .show()
                    }
                }
                row.addView(dot)
                row.addView(tvNome)
                row.addView(btnCambia)
                layout.addView(row)
            }
            AlertDialog.Builder(this@MainActivity)
                .setTitle("Colori topic")
                .setView(scroll)
                .setPositiveButton("Chiudi", null)
                .show()
        }
    }

    private fun mostraMenuContestuale(item: SpesaItem, anchor: android.view.View) {
        PopupMenu(this, anchor).apply {
            menuInflater.inflate(R.menu.item_context_menu, menu)
            setOnMenuItemClickListener { menuItem ->
                when (menuItem.itemId) {
                    R.id.action_add_foto -> mostraDialogSorgenteFoto(item.id)
                    R.id.action_elimina  -> eliminaConferma(item)
                }
                true
            }
            show()
        }
    }

    private fun mostraDialogSorgenteFoto(itemId: Int) {
        pendingFotoItemId = itemId
        AlertDialog.Builder(this)
            .setTitle(R.string.aggiungi_foto)
            .setItems(arrayOf(
                getString(R.string.fotocamera),
                getString(R.string.galleria)
            )) { _, which ->
                when (which) {
                    0 -> requestCameraPermission.launch(android.Manifest.permission.CAMERA)
                    1 -> pickImageLauncher.launch("image/*")
                }
            }
            .show()
    }

    private fun launchCamera() {
        val file = File(cacheDir, "foto_tmp_${System.currentTimeMillis()}.jpg")
        cameraImageUri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
        takePhotoLauncher.launch(cameraImageUri)
    }

    private fun uploadFotoFromUri(uri: Uri, itemId: Int) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val bytes = contentResolver.openInputStream(uri)?.readBytes()
                        ?: throw Exception("Impossibile leggere l'immagine")
                    ApiClient.uploadFoto(itemId, bytes)
                }
            }
            result.onSuccess { aggiornaLista() }
                  .onFailure { Toast.makeText(this@MainActivity, "Errore upload foto", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun apriFoto(item: SpesaItem) {
        startActivity(android.content.Intent(this, FotoActivity::class.java).apply {
            putExtra(FotoActivity.EXTRA_ITEM_ID, item.id)
            putExtra(FotoActivity.EXTRA_NOME, item.nome)
        })
    }
    private fun aggiornaLista() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getLista(gruppoId, topicId, userId) }
            }
            result.onSuccess { nuovi ->
                items.clear()
                items.addAll(nuovi)
                adapter.notifyDataSetChanged()
            }.onFailure {
                Toast.makeText(this@MainActivity, "Connessione fallita: ${it.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun toggleItem(item: SpesaItem) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.toggleItem(gruppoId, item.id, userId) }
            }
            result.onSuccess { aggiornaLista() }
                  .onFailure { Toast.makeText(this@MainActivity, "Errore toggle", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun eliminaConferma(item: SpesaItem) {
        AlertDialog.Builder(this)
            .setTitle("Elimina articolo")
            .setMessage("Eliminare \"${item.nome}\"?")
            .setPositiveButton("Elimina") { _, _ -> eliminaItem(item) }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun eliminaItem(item: SpesaItem) {
        val pos = items.indexOfFirst { it.id == item.id }.takeIf { it >= 0 } ?: return
        items.removeAt(pos)
        adapter.notifyItemRemoved(pos)
        lifecycleScope.launch {
            withContext(Dispatchers.IO) {
                runCatching { ApiClient.deleteItem(gruppoId, item.id, userId) }
            }
        }
    }

    private fun mostraDialogAggiungi() {
        val input = EditText(this).apply {
            hint = "es. Latte, Pane, Uova"
            setPadding(48, 16, 48, 16)
        }
        AlertDialog.Builder(this)
            .setTitle("Aggiungi articoli")
            .setView(input)
            .setPositiveButton("Aggiungi") { _, _ ->
                val testo = input.text.toString().trim()
                if (testo.isNotEmpty()) aggiungiItem(testo)
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun aggiungiItem(testo: String) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.addItem(gruppoId, topicId, testo, userId) }
            }
            result.onSuccess { aggiornaLista() }
                  .onFailure { Toast.makeText(this@MainActivity, "Errore aggiunta", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun caricaInfoGruppo() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val gId    = gruppoId
                    val tId    = topicId
                    val gruppi = ApiClient.getGruppiTyped()
                    val topics = ApiClient.getTopics(gId)
                    val gNome  = if (gId == 0) "Lista Personale"
                                 else gruppi.find { it.id == gId }?.nome ?: "Lista"
                    val tNome  = if (gId == 0) ""
                                 else topics.find { it.topicId == tId }?.nome ?: "Principale"
                    Triple(gNome, tNome, gId)
                }
            }
            result.onSuccess { (gNome, tNome, gId) ->
                tvGruppo.text = "$gNome \u25BE"
                tvTopic.text  = if (tNome.isEmpty()) "" else "$tNome \u25BE"
                tvTopic.visibility = if (tNome.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
                applicaColoreToolbar(gId, tNome)
                // aggiorna sottotitolo header drawer
                val header = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navView).getHeaderView(0)
                header.findViewById<TextView>(R.id.tvGruppoNome).text =
                    if (gId == 0) "🔒 Lista Personale" else "$gNome${if (tNome.isNotEmpty()) " • $tNome" else ""}"
            }
        }
    }

    private fun mostraDialogCambioTopic() {
        lifecycleScope.launch {
            val topics = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getTopics(gruppoId) }.getOrDefault(emptyList())
            }
            if (topics.isEmpty()) return@launch
            android.app.AlertDialog.Builder(this@MainActivity)
                .setTitle(getString(R.string.seleziona_topic))
                .setItems(topics.map { it.nome }.toTypedArray()) { _, idx ->
                    val topic = topics[idx]
                    prefs().edit().putInt("topic_id", topic.topicId).apply()
                    aggiornaLista()
                    caricaInfoGruppo()
                }
                .show()
        }
    }

    private fun mostraDialogCambioGruppo() {
        lifecycleScope.launch {
            val gruppi = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getGruppiTyped() }.getOrDefault(emptyList())
            }
            if (gruppi.isEmpty()) return@launch
            android.app.AlertDialog.Builder(this@MainActivity)
                .setTitle(getString(R.string.seleziona_gruppo))
                .setItems(gruppi.map { it.nome }.toTypedArray()) { _, idx ->
                    val gruppo = gruppi[idx]
                    lifecycleScope.launch {
                        val topics = withContext(Dispatchers.IO) {
                            runCatching { ApiClient.getTopics(gruppo.id) }.getOrDefault(emptyList())
                        }
                        android.app.AlertDialog.Builder(this@MainActivity)
                            .setTitle(getString(R.string.seleziona_topic))
                            .setItems(topics.map { it.nome }.toTypedArray()) { _, tIdx ->
                                val topic = topics[tIdx]
                                prefs().edit()
                                    .putInt("gruppo_id", gruppo.id)
                                    .putInt("topic_id", topic.topicId)
                                    .apply()
                                aggiornaLista()
                                caricaInfoGruppo()
                            }
                            .show()
                    }
                }
                .show()
        }
    }

    private fun prefs() = getSharedPreferences("botspesa_prefs", Context.MODE_PRIVATE)
}
