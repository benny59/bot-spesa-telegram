package com.botspesa.app

import android.app.AlertDialog
import android.content.Context
import android.content.Intent
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
import androidx.core.content.ContextCompat
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
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class MainActivity : AppCompatActivity() {

    private data class AddDestination(
        val gruppoId: Int,
        val topicId: Int,
        val label: String
    )

    private lateinit var recyclerView: RecyclerView
    private lateinit var adapter: SpesaAdapter
    private lateinit var drawerLayout: DrawerLayout
    private lateinit var tvGruppo: TextView
    private lateinit var tvTopic: TextView
    private val items = mutableListOf<SpesaItem>()
    private var pendingFotoItemId = 0
    private var pendingNuovoArticolo: String? = null
    private var pendingNuovoGruppoId = 0
    private var pendingNuovoTopicId = 0
    private var cameraImageUri: Uri? = null
    // "": vista normale, "tutti": tutti gli articoli, "miei": i miei articoli
    private var vistaAttuale: String = ""

    private val pickImageLauncher = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri?.let(::gestisciFotoSelezionata)
    }
    private val takePhotoLauncher = registerForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        if (ok) cameraImageUri?.let(::gestisciFotoSelezionata)
    }
    private val requestCameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        if (ok) launchCamera() else Toast.makeText(this, "Permesso fotocamera negato", Toast.LENGTH_SHORT).show()
    }

    private val gruppoId  get() = prefs().getInt("gruppo_id", 1)
    private val topicId   get() = prefs().getInt("topic_id", 0)
    private val userId    get() = prefs().getInt("user_id", 0)
    private val firstName get() = prefs().getString("user_first_name", "") ?: ""
    private val lastName  get() = prefs().getString("user_last_name", "") ?: ""
    private val isCreator get() = prefs().getBoolean("is_creator", false)

    private fun aggiornaNomeUtente() {
        val navView = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navView)
        val header = navView.getHeaderView(0)
        val tvUser = header.findViewById<TextView>(R.id.tvUserName)
        val nome = listOf(firstName, lastName).filter { it.isNotEmpty() }.joinToString(" ")
        if (nome.isNotEmpty()) tvUser.text = "👤 $nome"
        else tvUser.text = if (userId != 0) "👤 utente collegato" else "(non collegato)"

        // Aggiorna sempre dal server per tenere is_creator sincronizzato
        if (userId != 0) {
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) {
                    runCatching { ApiClient.fetchMe(userId) }.getOrNull()
                }
                if (result != null) {
                    prefs().edit()
                        .putString("user_first_name", result.firstName)
                        .putString("user_last_name",  result.lastName)
                        .putBoolean("is_creator",     result.isCreator)
                        .apply()
                    val n = listOf(result.firstName, result.lastName).filter { it.isNotEmpty() }.joinToString(" ")
                    tvUser.text = "👤 $n"
                    aggiornaVisibilitaAdmin()
                }
            }
        }
    }

    private fun aggiornaVisibilitaAdmin() {
        val navView = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navView)
        navView.menu.findItem(R.id.nav_amministrazione)?.isVisible = isCreator
    }

    private fun mostraEsitoBreve(testo: String, successo: Boolean) {
        val snackbar = Snackbar.make(drawerLayout, testo, Snackbar.LENGTH_SHORT)
        val sfondo = if (successo) Color.parseColor("#2E7D32") else Color.parseColor("#C62828")
        snackbar.view.setBackgroundColor(sfondo)
        snackbar.setTextColor(Color.WHITE)
        snackbar.setActionTextColor(Color.WHITE)
        snackbar.show()
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
            onContext  = ::selezionaContestoDaListaGlobale,
            contextColor = ::coloreSeparatoreContesto,
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

        val navHeader = findViewById<NavigationView>(R.id.navView).getHeaderView(0)
        navHeader.findViewById<TextView>(R.id.tvAppName).text =
            getString(R.string.app_name_version, BuildConfig.VERSION_NAME)

        findViewById<NavigationView>(R.id.navView).setNavigationItemSelectedListener { item ->
            drawerLayout.closeDrawers()
            when (item.itemId) {
                R.id.nav_lista            -> { vistaAttuale = ""; aggiornaLista(); caricaInfoGruppo(); invalidateOptionsMenu() }
                R.id.nav_tutti            -> { vistaAttuale = "tutti"; aggiornaLista(); caricaInfoGruppo(); invalidateOptionsMenu() }
                R.id.nav_miei             -> { vistaAttuale = "miei"; aggiornaLista(); caricaInfoGruppo(); invalidateOptionsMenu() }
                R.id.nav_checklist        -> {
                    val gNome = tvGruppo.text.toString().trimEnd('▾', ' ').trim()
                    val tNome = tvTopic.text.toString().trimEnd('▾', ' ').trim()
                    ChecklistSheet.newInstance(gruppoId, topicId, userId, gNome, tNome)
                        .also { it.setOnItemChangedListener { aggiornaLista() } }
                        .show(supportFragmentManager, "checklist")
                }
                    R.id.nav_storico          -> {
                        val gNome = tvGruppo.text.toString().trimEnd('▾', ' ').trim()
                        val tNome = tvTopic.text.toString().trimEnd('▾', ' ').trim()
                        StoricoAcquistiSheet.newInstance(gruppoId, topicId, gNome, tNome)
                        .show(supportFragmentManager, "storico_acquisti")
                    }
                R.id.nav_gestione_carte    -> apriGestioneCarte()
                R.id.nav_cambia_gruppo     -> mostraDialogCambioGruppo()
                R.id.nav_collega_telegram  -> mostraDialogCollegaTelegram()
                R.id.nav_config_rete       -> mostraDialogConfigRete()
                R.id.nav_colori_gruppi     -> mostraDialogColoriTopic()
                R.id.nav_amministrazione   -> AdminSheet.newInstance(userId).show(supportFragmentManager, "admin")
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

        aggiornaNomeUtente()
        if (prefs.contains("api_url")) {
            aggiornaLista()
            caricaInfoGruppo()
            if (prefs.getInt("user_id", 0) == 0) {
                mostraDialogCollegaTelegram(primoAvvio = true)
            }
        } else {
            mostraDialogConfigRete(primoAvvio = true)
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

    override fun onPrepareOptionsMenu(menu: Menu): Boolean {
        menu.findItem(R.id.action_condividi)?.isVisible = vistaAttuale.isEmpty()
        return super.onPrepareOptionsMenu(menu)
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean {
        return when (item.itemId) {
            R.id.action_scopetta -> { mostraScopettaConferma(); true }
            R.id.action_condividi -> { condividiListaCorrente(); true }
            R.id.action_carte    -> { CarteSheet.newInstance(gruppoId, userId).show(supportFragmentManager, "carte"); true }
            else -> super.onOptionsItemSelected(item)
        }
    }

    private fun condividiListaCorrente() {
        val daComprare = items.filterNot { it.isBought }
        if (daComprare.isEmpty()) {
            Toast.makeText(this, "Nessun articolo da condividere", Toast.LENGTH_SHORT).show()
            return
        }

        val nomeGruppo = tvGruppo.text.toString().trimEnd('▾', ' ').trim()
        val nomeTopic = tvTopic.text.toString().trimEnd('▾', ' ').trim()
        val aggiornatoIl = LocalDateTime.now().format(DateTimeFormatter.ofPattern("dd/MM/yyyy 'alle' HH:mm"))
        val testo = buildString {
            appendLine("🛒 Lista spesa: $nomeGruppo")
            if (nomeTopic.isNotEmpty()) appendLine("📍 Reparto: $nomeTopic")
            appendLine()
            daComprare.forEach { appendLine("• ${it.nome}") }
            appendLine()
            append("Aggiornata il $aggiornatoIl")
        }

        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_SUBJECT, "Lista spesa: $nomeGruppo")
            putExtra(Intent.EXTRA_TEXT, testo)
        }
        startActivity(Intent.createChooser(intent, getString(R.string.scegli_app_condivisione)))
    }

    private fun mostraScopettaConferma() {
        val comprati = items.count { it.isBought }
        if (comprati == 0) {
            Toast.makeText(this, "Nessun articolo comprato", Toast.LENGTH_SHORT).show()
            return
        }
        val titolo = if (vistaAttuale.isNotEmpty()) "🧹 Superscopetta" else getString(R.string.scopetta)
        val msg = if (vistaAttuale.isNotEmpty())
            "Rimuovere da tutti i gruppi gli articoli segnati come comprati da te?"
        else
            "Rimuovere $comprati articol${if (comprati == 1) "o comprato" else "i comprati"}?"
        AlertDialog.Builder(this)
            .setTitle(titolo)
            .setMessage(msg)
            .setPositiveButton("Rimuovi") { _, _ -> eseguiScopetta() }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun eseguiScopetta() {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                if (vistaAttuale.isNotEmpty())
                    runCatching { ApiClient.superScopetta(userId) }.getOrDefault(false)
                else
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
            coloreListaPersonale()
        } else {
            coloreTopic(gruppoId, topicId, topicNome)
        }
        findViewById<androidx.appcompat.widget.Toolbar>(R.id.toolbar).setBackgroundColor(color)
        window.statusBarColor = color
    }

    private fun coloreSeparatoreContesto(item: SpesaItem): Int {
        if (item.gruppoId == 0) return coloreListaPersonale()
        val topicNome = item.nomeTopic.ifEmpty {
            item.nomeContesto.substringAfter(" • ", "")
        }
        return coloreTopic(item.gruppoId, item.topicId, topicNome)
    }

    private fun coloreListaPersonale(): Int = prefs().getInt(
        "personal_list_color",
        Color.parseColor("#455A64")
    )

    private fun coloreTopic(gruppoId: Int, topicId: Int, topicNome: String): Int {
        val p = prefs()
        val colorKey = "topic_color_${gruppoId}_$topicId"
        val legacyKey = "topic_color_$topicId"
        return when {
            p.contains(colorKey) -> p.getInt(colorKey, 0)
            p.contains(legacyKey) -> p.getInt(legacyKey, 0)
            else -> topicColorDefault(topicNome)
        }
    }

    // Swipe destra = toggle comprato, swipe sinistra = soft delete / undo
    private val swipeCallback = object : ItemTouchHelper.SimpleCallback(
        0, ItemTouchHelper.RIGHT or ItemTouchHelper.LEFT
    ) {
        override fun onMove(rv: RecyclerView, vh: RecyclerView.ViewHolder, t: RecyclerView.ViewHolder) = false

        override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            val pos = viewHolder.adapterPosition
            if (pos == RecyclerView.NO_POSITION) return
            val item = items[pos]
            adapter.notifyItemChanged(pos)
            when (direction) {
                ItemTouchHelper.RIGHT -> toggleItem(item)
                ItemTouchHelper.LEFT -> toggleDeleteItem(item)
            }
        }
    }

    private fun mostraDialogImpostazioni() = mostraDialogConfigRete()

    private fun apriGestioneCarte() {
        // Recupera il nome del gruppo attuale per mostrarlo nella sezione condivisioni
        val gNome = tvGruppo.text.toString().trimEnd('▾', ' ')
        GestioneCarteSheet.newInstance(gruppoId, userId, gNome)
            .show(supportFragmentManager, "gestione_carte")
    }

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
                            prefs().edit()
                                .putInt("user_id", r.userId)
                                .putString("user_first_name", r.firstName)
                                .apply()
                            aggiornaNomeUtente()
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

    private fun mostraDialogConfigRete(primoAvvio: Boolean = false) {
        val p = prefs()
        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(48, 16, 48, 8)
        }
        val etUrl = EditText(this).apply {
            hint = "http://IP:4568  oppure  http://hostname:4568"
            setText(p.getString("api_url", "http://10.0.2.2:4567"))
            inputType = android.text.InputType.TYPE_CLASS_TEXT or android.text.InputType.TYPE_TEXT_VARIATION_URI
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
        val dlg = AlertDialog.Builder(this)
            .setTitle(getString(R.string.nav_config_rete))
            .setView(layout)
            .setPositiveButton("Salva", null)
            .also { if (!primoAvvio) it.setNegativeButton("Annulla", null) }
            .create()
        dlg.setOnShowListener {
            dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val url   = etUrl.text.toString().trimEnd('/')
                val token = etToken.text.toString().trim()
                if (!url.startsWith("http://") && !url.startsWith("https://")) {
                    etUrl.error = "Inserisci un URL completo, per esempio http://192.168.1.10:4568"
                    return@setOnClickListener
                }
                ApiClient.configure(url = url, tok = token)
                dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                lifecycleScope.launch {
                    val raggiungibile = withContext(Dispatchers.IO) { ApiClient.ping() }
                    dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                    if (!raggiungibile) {
                        etUrl.error = "Server non raggiungibile"
                        return@launch
                    }
                    p.edit().putString("api_url", url).putString("api_token", token).apply()
                    dlg.dismiss()
                    aggiornaLista()
                    caricaInfoGruppo()
                    if (primoAvvio && userId == 0) {
                        mostraDialogCollegaTelegram(primoAvvio = true)
                    }
                }
            }
        }
        dlg.show()
    }

    private fun mostraDialogColoriTopic() {
        lifecycleScope.launch {
            val personalList = gruppoId == 0
            val topics = if (personalList) {
                listOf(TopicItem(0, "Lista Personale"))
            } else {
                withContext(Dispatchers.IO) {
                    runCatching { ApiClient.getTopics(gruppoId) }.getOrDefault(emptyList())
                }
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
                val colorKey = if (personalList) "personal_list_color"
                               else "topic_color_${gruppoId}_${topic.topicId}"
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
                        setColor(if (personalList) coloreListaPersonale()
                                 else coloreTopic(gruppoId, topic.topicId, topic.nome))
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
                                if (personalList || topicId == topic.topicId) {
                                    applicaColoreToolbar(gruppoId, topic.nome)
                                }
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
            menu.findItem(R.id.action_elimina_foto).isVisible = item.hasFoto
            menu.findItem(R.id.action_sposta_topic).isVisible = item.gruppoId != 0
            setOnMenuItemClickListener { menuItem ->
                when (menuItem.itemId) {
                    R.id.action_modifica -> mostraDialogModificaItem(item)
                    R.id.action_add_foto -> mostraDialogSorgenteFoto(item.id)
                    R.id.action_elimina_foto -> eliminaFotoConferma(item)
                    R.id.action_sposta_topic -> mostraDialogSpostaItem(item)
                    R.id.action_elimina  -> eliminaConferma(item)
                }
                true
            }
            show()
        }
    }

    private fun mostraDialogModificaItem(item: SpesaItem) {
        val input = EditText(this).apply {
            setText(item.nome)
            setSelection(text.length)
            setPadding(48, 16, 48, 16)
        }
        val dialog = AlertDialog.Builder(this)
            .setTitle(R.string.modifica_articolo)
            .setView(input)
            .setPositiveButton("Salva", null)
            .setNegativeButton("Annulla", null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val nome = input.text.toString().trim()
                if (nome.isEmpty()) input.error = "Il testo non può essere vuoto"
                else {
                    dialog.dismiss()
                    lifecycleScope.launch {
                        val ok = withContext(Dispatchers.IO) {
                            runCatching { ApiClient.updateItem(item.id, nome, userId) }.getOrDefault(false)
                        }
                        if (ok) aggiornaLista()
                        else Toast.makeText(this@MainActivity, "Modifica non riuscita", Toast.LENGTH_SHORT).show()
                    }
                }
            }
        }
        dialog.show()
    }

    private fun eliminaFotoConferma(item: SpesaItem) {
        AlertDialog.Builder(this)
            .setTitle(R.string.elimina_foto)
            .setMessage("Eliminare la foto associata a \"${item.nome}\"?")
            .setPositiveButton("Elimina") { _, _ ->
                lifecycleScope.launch {
                    val ok = withContext(Dispatchers.IO) {
                        runCatching { ApiClient.deleteFoto(item.id, userId) }.getOrDefault(false)
                    }
                    if (ok) aggiornaLista()
                    else Toast.makeText(this@MainActivity, "Eliminazione foto non riuscita", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun mostraDialogSpostaItem(item: SpesaItem) {
        lifecycleScope.launch {
            val topics = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getTopics(item.gruppoId) }.getOrDefault(emptyList())
            }.filter { it.topicId != item.topicId }
            if (topics.isEmpty()) {
                Toast.makeText(this@MainActivity, "Nessun altro topic disponibile", Toast.LENGTH_SHORT).show()
                return@launch
            }
            AlertDialog.Builder(this@MainActivity)
                .setTitle(R.string.sposta_topic)
                .setItems(topics.map { it.nome }.toTypedArray()) { _, index ->
                    lifecycleScope.launch {
                        val ok = withContext(Dispatchers.IO) {
                            runCatching { ApiClient.moveItem(item.id, topics[index].topicId, userId) }.getOrDefault(false)
                        }
                        if (ok) aggiornaLista()
                        else Toast.makeText(this@MainActivity, "Spostamento non riuscito", Toast.LENGTH_SHORT).show()
                    }
                }
                .show()
        }
    }

    private fun mostraDialogSorgenteFoto(itemId: Int) {
        pendingFotoItemId = itemId
        pendingNuovoArticolo = null
        mostraDialogSorgenteFoto()
    }

    private fun mostraDialogSorgenteFotoNuovo(testo: String, destinazione: AddDestination) {
        pendingFotoItemId = 0
        pendingNuovoArticolo = testo
        pendingNuovoGruppoId = destinazione.gruppoId
        pendingNuovoTopicId = destinazione.topicId
        mostraDialogSorgenteFoto()
    }

    private fun mostraDialogSorgenteFoto() {
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

    private fun gestisciFotoSelezionata(uri: Uri) {
        val nuovoArticolo = pendingNuovoArticolo
        val itemId = pendingFotoItemId
        val nuovoGruppoId = pendingNuovoGruppoId
        val nuovoTopicId = pendingNuovoTopicId
        pendingNuovoArticolo = null
        pendingFotoItemId = 0
        pendingNuovoGruppoId = 0
        pendingNuovoTopicId = 0
        if (nuovoArticolo != null) aggiungiItemConFoto(nuovoArticolo, uri, nuovoGruppoId, nuovoTopicId)
        else if (itemId != 0) uploadFotoFromUri(uri, itemId)
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
                    ApiClient.uploadFoto(itemId, userId, bytes)
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
                runCatching {
                    when (vistaAttuale) {
                        "tutti" -> ApiClient.getTutti(userId)
                        "miei"  -> ApiClient.getMiei(userId)
                        else    -> ApiClient.getLista(gruppoId, topicId, userId)
                    }
                }
            }
            result.onSuccess { nuovi ->
                items.clear()
                items.addAll(nuovi)
                adapter.notifyDataSetChanged()
                aggiornaConteggiDrawer()
            }.onFailure {
                Toast.makeText(this@MainActivity, "Connessione fallita: ${it.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // Usato da ChecklistSheet per aggiornare la lista principale dopo un toggle
    fun refreshLista() = aggiornaLista()

    private fun aggiornaConteggiDrawer() {
        if (userId == 0) return
        lifecycleScope.launch {
            val conteggi = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getConteggiListe(userId) }.getOrNull()
            } ?: return@launch
            val menu = findViewById<NavigationView>(R.id.navView).menu
            menu.findItem(R.id.nav_tutti).title = "Tutti gli articoli (${conteggi.tutti})"
            menu.findItem(R.id.nav_miei).title = "I miei articoli (${conteggi.miei})"
        }
    }

    private fun selezionaContestoDaListaGlobale(item: SpesaItem) {
        prefs().edit()
            .putInt("gruppo_id", item.gruppoId)
            .putInt("topic_id", item.topicId)
            .apply()
        vistaAttuale = ""
        findViewById<NavigationView>(R.id.navView).setCheckedItem(R.id.nav_lista)
        aggiornaLista()
        caricaInfoGruppo()
        invalidateOptionsMenu()
        Toast.makeText(this, "Contesto: ${item.nomeContesto}", Toast.LENGTH_SHORT).show()
    }

    private fun toggleItem(item: SpesaItem) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.toggleItem(item.gruppoId, item.id, userId) }
            }
            result.onSuccess { aggiornaLista() }
                  .onFailure { Toast.makeText(this@MainActivity, "Errore toggle", Toast.LENGTH_SHORT).show() }
        }
    }

    private fun eliminaConferma(item: SpesaItem) {
        val titolo = if (item.deleted) "Ripristina articolo" else "Cancella articolo"
        val messaggio = if (item.deleted) {
            "Ripristinare \"${item.nome}\" nella lista?"
        } else {
            "Cancellare \"${item.nome}\"?\nL’item resterà visibile in fondo alla lista e potrà essere ripristinato."
        }
        AlertDialog.Builder(this)
            .setTitle(titolo)
            .setMessage(messaggio)
            .setPositiveButton(if (item.deleted) "Ripristina" else "Cancella") { _, _ ->
                if (item.deleted) restoreItem(item) else eliminaItem(item)
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun eliminaItem(item: SpesaItem) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { ApiClient.deleteItem(item.gruppoId, item.id, userId) }.getOrDefault(false)
            }
            if (ok) {
                aggiornaLista()
                mostraEsitoBreve("Articolo cancellato", true)
            } else {
                Toast.makeText(this@MainActivity, "Cancellazione non riuscita", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun restoreItem(item: SpesaItem) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { ApiClient.restoreItem(item.gruppoId, item.id, userId) }.getOrDefault(false)
            }
            if (ok) {
                aggiornaLista()
                mostraEsitoBreve("Articolo ripristinato", true)
            } else {
                Toast.makeText(this@MainActivity, "Ripristino non riuscito", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun toggleDeleteItem(item: SpesaItem) {
        if (item.deleted) restoreItem(item)
        else eliminaItem(item)
    }

    private fun mostraDialogAggiungi() {
        lifecycleScope.launch {
            val destinazioni = withContext(Dispatchers.IO) {
                runCatching {
                    val gruppi = ApiClient.getGruppiTyped(userId).filter { it.id != 0 }
                    buildList {
                        add(AddDestination(0, 0, "Personale"))
                        gruppi.forEach { gruppo ->
                            ApiClient.getTopics(gruppo.id).forEach { topic ->
                                add(AddDestination(
                                    gruppo.id,
                                    topic.topicId,
                                    "${gruppo.nome}: ${topic.nome}"
                                ))
                            }
                        }
                    }
                }
            }.getOrElse {
                Toast.makeText(this@MainActivity, "Impossibile caricare le destinazioni", Toast.LENGTH_SHORT).show()
                return@launch
            }

            val input = EditText(this@MainActivity).apply {
                hint = "es. Latte, Pane, Uova"
                setPadding(0, 16, 0, 16)
            }
            val radioGroup = android.widget.RadioGroup(this@MainActivity).apply {
                orientation = android.widget.RadioGroup.VERTICAL
            }
            val currentIndex = destinazioni.indexOfFirst {
                it.gruppoId == gruppoId && it.topicId == topicId
            }.takeIf { it >= 0 } ?: 0
            destinazioni.forEachIndexed { index, destinazione ->
                radioGroup.addView(android.widget.RadioButton(this@MainActivity).apply {
                    id = android.view.View.generateViewId()
                    text = destinazione.label
                    tag = index
                    isChecked = index == currentIndex
                })
            }
            val dp = resources.displayMetrics.density
            val content = android.widget.LinearLayout(this@MainActivity).apply {
                orientation = android.widget.LinearLayout.VERTICAL
                setPadding((24 * dp).toInt(), 0, (24 * dp).toInt(), 0)
                addView(input)
                addView(TextView(this@MainActivity).apply {
                    text = "Destinazione"
                    textSize = 14f
                    setPadding(0, (8 * dp).toInt(), 0, (4 * dp).toInt())
                })
                addView(android.widget.ScrollView(this@MainActivity).apply {
                    addView(radioGroup)
                }, android.widget.LinearLayout.LayoutParams(
                    android.widget.LinearLayout.LayoutParams.MATCH_PARENT,
                    (280 * dp).toInt()
                ))
            }
            val dlg = AlertDialog.Builder(this@MainActivity)
                .setTitle("Aggiungi articoli")
                .setView(content)
                .setPositiveButton("Aggiungi", null)
                .setNeutralButton("Con foto", null)
                .setNegativeButton("Annulla", null)
                .create()
            fun destinazioneSelezionata(): AddDestination {
                val radio = radioGroup.findViewById<android.widget.RadioButton>(radioGroup.checkedRadioButtonId)
                return destinazioni[radio.tag as Int]
            }
            dlg.setOnShowListener {
                dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    val testo = input.text.toString().trim()
                    if (testo.isEmpty()) {
                        input.error = "Inserisci almeno un articolo"
                    } else {
                        dlg.dismiss()
                        aggiungiItem(testo, destinazioneSelezionata())
                    }
                }
                dlg.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener {
                    val testo = input.text.toString().trim()
                    when {
                        testo.isEmpty() -> input.error = "Inserisci un articolo"
                        testo.contains(',') -> input.error = "Con una foto puoi aggiungere un articolo alla volta"
                        else -> {
                            dlg.dismiss()
                            mostraDialogSorgenteFotoNuovo(testo, destinazioneSelezionata())
                        }
                    }
                }
            }
            dlg.show()
        }
    }

    private fun aggiungiItem(testo: String, destinazione: AddDestination) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    ApiClient.addItem(destinazione.gruppoId, destinazione.topicId, testo, userId)
                        .also { if (it.isEmpty()) throw IllegalStateException("Articolo non creato") }
                }
            }
            result.onSuccess {
                aggiornaLista()
                mostraEsitoBreve("Aggiunto in ${destinazione.label}", true)
            }.onFailure {
                mostraEsitoBreve(it.message ?: "Errore aggiunta", false)
            }
        }
    }

    private fun aggiungiItemConFoto(testo: String, uri: Uri, targetGruppoId: Int, targetTopicId: Int) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                        ?: throw Exception("Impossibile leggere l'immagine")
                    val itemId = ApiClient.addItem(targetGruppoId, targetTopicId, testo, userId).firstOrNull()
                        ?: throw Exception("Articolo non creato")
                    if (!ApiClient.uploadFoto(itemId, userId, bytes)) {
                        throw Exception("Foto non caricata")
                    }
                }
            }
            result.onSuccess {
                aggiornaLista()
                mostraEsitoBreve("Aggiunto con foto", true)
            }.onFailure {
                mostraEsitoBreve(it.message ?: "Errore aggiunta foto", false)
            }
        }
    }

    private fun caricaInfoGruppo() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val gId    = gruppoId
                    val tId    = topicId
                    val gruppi = ApiClient.getGruppiTyped(userId)
                    val topics = ApiClient.getTopics(gId)
                    val gNome  = if (gId == 0) "Lista Personale"
                                 else gruppi.find { it.id == gId }?.nome ?: "Lista"
                    val tNome  = if (gId == 0) ""
                                 else topics.find { it.topicId == tId }?.nome ?: "Principale"
                    Triple(gNome, tNome, gId)
                }
            }
            result.onSuccess { (gNome, tNome, gId) ->
                when (vistaAttuale) {
                    "tutti" -> {
                        tvGruppo.text = "Tutti gli articoli"
                        tvTopic.visibility = android.view.View.GONE
                        applicaColoreToolbar(0, "")
                    }
                    "miei" -> {
                        tvGruppo.text = "I miei articoli"
                        tvTopic.visibility = android.view.View.GONE
                        applicaColoreToolbar(0, "")
                    }
                    else -> {
                        tvGruppo.text = "$gNome \u25BE"
                        tvTopic.text  = if (tNome.isEmpty()) "" else "$tNome \u25BE"
                        tvTopic.visibility = if (tNome.isEmpty()) android.view.View.GONE else android.view.View.VISIBLE
                        applicaColoreToolbar(gId, tNome)
                    }
                }
                // aggiorna sottotitolo header drawer
                val header = findViewById<com.google.android.material.navigation.NavigationView>(R.id.navView).getHeaderView(0)
                header.findViewById<TextView>(R.id.tvGruppoNome).text =
                    if (gId == 0) "🔒 Lista Personale" else "$gNome${if (tNome.isNotEmpty()) " • $tNome" else ""}"
            }
        }
    }

    private fun mostraDialogCambioTopic() {
        if (gruppoId == 0) return  // Lista Personale non ha topics
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
                runCatching { ApiClient.getGruppiTyped(userId) }.getOrDefault(emptyList())
            }
            if (gruppi.isEmpty()) return@launch
            android.app.AlertDialog.Builder(this@MainActivity)
                .setTitle(getString(R.string.seleziona_gruppo))
                .setItems(gruppi.map { it.nome }.toTypedArray()) { _, idx ->
                    val gruppo = gruppi[idx]
                    lifecycleScope.launch {
                        if (gruppo.id == 0) {
                            // Lista Personale: nessun topic, salva direttamente
                            prefs().edit().putInt("gruppo_id", 0).putInt("topic_id", 0).apply()
                            aggiornaLista()
                            caricaInfoGruppo()
                            return@launch
                        }
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
