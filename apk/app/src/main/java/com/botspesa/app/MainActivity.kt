package com.botspesa.app

import android.app.AlertDialog
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.widget.EditText
import android.widget.PopupMenu
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
        val toggle = ActionBarDrawerToggle(
            this, drawerLayout, toolbar,
            R.string.open_drawer, R.string.close_drawer
        )
        drawerLayout.addDrawerListener(toggle)
        toggle.syncState()

        findViewById<NavigationView>(R.id.navView).setNavigationItemSelectedListener { item ->
            drawerLayout.closeDrawers()
            when (item.itemId) {
                R.id.nav_carte         -> CarteSheet.newInstance(gruppoId).show(supportFragmentManager, "carte")
                R.id.nav_cambia_gruppo -> mostraDialogCambioGruppo()
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
                runCatching { ApiClient.getLista(gruppoId, topicId) }
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
                    val gruppi  = ApiClient.getGruppiTyped()
                    val topics  = ApiClient.getTopics(gruppoId)
                    val gNome   = gruppi.find { it.id == gruppoId }?.nome ?: "Lista"
                    val tNome   = topics.find { it.topicId == topicId }?.nome ?: "Principale"
                    Pair(gNome, tNome)
                }
            }
            result.onSuccess { (gNome, tNome) ->
                supportActionBar?.title    = gNome
                supportActionBar?.subtitle = tNome
            }
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
