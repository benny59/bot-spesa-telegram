package com.botspesa.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CatalogoProdottiSheet : BottomSheetDialogFragment() {
    private var onItemAdded: (() -> Unit)? = null
    private var onInfo: ((ApiClient.CatalogProduct) -> Unit)? = null

    private val gruppoId get() = requireArguments().getInt(ARG_GRUPPO_ID)
    private val topicId get() = requireArguments().getInt(ARG_TOPIC_ID)
    private val userId get() = requireArguments().getInt(ARG_USER_ID)

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, state: Bundle?): View =
        inflater.inflate(R.layout.fragment_catalogo_prodotti, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val input = view.findViewById<EditText>(R.id.etRicercaProdotti)
        val recycler = view.findViewById<RecyclerView>(R.id.rvCatalogoProdotti)
        val empty = view.findViewById<TextView>(R.id.tvCatalogoProdottiVuoto)
        val progress = view.findViewById<ProgressBar>(R.id.progressCatalogoProdotti)
        recycler.layoutManager = LinearLayoutManager(requireContext())

        var lastQuery = ""
        var toggleHandler: (ApiClient.CatalogProduct) -> Unit = {}

        // silent = true: ripete l'ultima ricerca senza nascondere i risultati (dopo aver aggiunto/tolto un articolo)
        fun search(silent: Boolean = false) {
            val query = if (silent) lastQuery else input.text.toString().trim()
            if (!silent) {
                input.clearFocus()
                val inputMethodManager = requireContext().getSystemService(InputMethodManager::class.java)
                inputMethodManager.hideSoftInputFromWindow(input.windowToken, 0)
                if (query.length < 2) {
                    input.error = getString(R.string.ricerca_minimo_due_caratteri)
                    return
                }
                progress.visibility = View.VISIBLE
                empty.visibility = View.GONE
                recycler.visibility = View.GONE
            }
            lastQuery = query
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) {
                    runCatching { ApiClient.searchProducts(query, userId, gruppoId, topicId) }
                }
                progress.visibility = View.GONE
                result.onSuccess { products ->
                    empty.text = getString(R.string.nessun_prodotto_trovato)
                    empty.visibility = if (products.isEmpty()) View.VISIBLE else View.GONE
                    recycler.visibility = if (products.isEmpty()) View.GONE else View.VISIBLE
                    recycler.adapter = CatalogAdapter(products, { toggleHandler(it) }, onInfo, ::openYuka)
                }.onFailure {
                    empty.text = it.message ?: getString(R.string.errore_generico)
                    empty.visibility = View.VISIBLE
                }
            }
        }

        // come nei Preferiti: il + inserisce subito in lista (nome, GTIN e link Yuka del prodotto), il ✓ toglie
        toggleHandler = { product ->
            lifecycleScope.launch {
                val result = withContext(Dispatchers.IO) {
                    runCatching {
                        val itemId = product.itemId
                        if (itemId != null) {
                            if (!ApiClient.removeItem(gruppoId, itemId, userId)) throw IllegalStateException("rimozione non riuscita")
                            false
                        } else {
                            ApiClient.addItem(
                                gruppoId = gruppoId,
                                topicId = topicId,
                                nome = product.description,
                                userId = userId,
                                linkUrl = product.yukaUrl.ifBlank { null },
                                gtin = product.gtin,
                                splitItems = false
                            ).also { if (it.isEmpty()) throw IllegalStateException("Articolo non creato") }
                            true
                        }
                    }
                }
                result.onSuccess { added ->
                    Toast.makeText(requireContext(), if (added) R.string.catalogo_aggiunto else R.string.catalogo_rimosso, Toast.LENGTH_SHORT).show()
                    onItemAdded?.invoke()
                    search(silent = true)
                }.onFailure {
                    Toast.makeText(requireContext(), it.message ?: getString(R.string.errore_generico), Toast.LENGTH_SHORT).show()
                }
            }
        }

        view.findViewById<View>(R.id.btnRicercaProdotti).setOnClickListener { search() }
        input.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEARCH) {
                search()
                true
            } else false
        }
    }

    private fun openYuka(product: ApiClient.CatalogProduct) {
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(product.yukaUrl))) }
            .onFailure { Toast.makeText(requireContext(), R.string.link_non_disponibile, Toast.LENGTH_SHORT).show() }
    }

    fun setOnItemAddedListener(listener: () -> Unit) {
        onItemAdded = listener
    }

    fun setOnInfoListener(listener: (ApiClient.CatalogProduct) -> Unit) {
        onInfo = listener
    }

    private class CatalogAdapter(
        private val products: List<ApiClient.CatalogProduct>,
        private val onToggle: (ApiClient.CatalogProduct) -> Unit,
        private val onInfo: ((ApiClient.CatalogProduct) -> Unit)?,
        private val onYuka: (ApiClient.CatalogProduct) -> Unit
    ) : RecyclerView.Adapter<CatalogAdapter.ViewHolder>() {
        class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val description: TextView = view.findViewById(R.id.tvCatalogoDescrizione)
            val gtin: TextView = view.findViewById(R.id.tvCatalogoGtin)
            val yuka: ImageView = view.findViewById(R.id.ivCatalogoYuka)
            val nutrition: ImageView = view.findViewById(R.id.ivCatalogoNutrition)
            val add: TextView = view.findViewById(R.id.tvCatalogoAggiungi)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) = ViewHolder(
            LayoutInflater.from(parent.context).inflate(R.layout.item_catalogo_prodotto, parent, false)
        )

        override fun getItemCount(): Int = products.size

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val product = products[position]
            holder.description.text = product.description
            holder.gtin.text = product.gtin
            holder.yuka.visibility = if (product.yukaUrl.isBlank()) View.GONE else View.VISIBLE
            holder.yuka.setOnClickListener { onYuka(product) }
            holder.nutrition.alpha = if (product.hasCard) 1f else 0.45f   // sbiadita senza dati OpenFood, come in lista
            holder.nutrition.setOnClickListener { onInfo?.invoke(product) }
            holder.add.text = if (product.inList) "✓" else "+"
            holder.add.setBackgroundResource(if (product.inList) R.drawable.circle_initials_green else R.drawable.circle_initials)
            holder.add.setOnClickListener { onToggle(product) }
        }
    }

    companion object {
        private const val ARG_GRUPPO_ID = "gruppo_id"
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_USER_ID = "user_id"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int) = CatalogoProdottiSheet().apply {
            arguments = Bundle().apply {
                putInt(ARG_GRUPPO_ID, gruppoId)
                putInt(ARG_TOPIC_ID, topicId)
                putInt(ARG_USER_ID, userId)
            }
        }
    }
}