package com.botspesa.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.NumberFormat
import java.util.Locale

class ChecklistSheet : BottomSheetDialogFragment() {

    private var onItemChanged: (() -> Unit)? = null

    private lateinit var adapter: ChecklistAdapter
    private val checklistItems = mutableListOf<ChecklistItem>()

    private val gruppoId   get() = arguments?.getInt(ARG_GRUPPO_ID)      ?: 0
    private val topicId    get() = arguments?.getInt(ARG_TOPIC_ID)       ?: 0
    private val userId     get() = arguments?.getInt(ARG_USER_ID)        ?: 0
    private val gruppoNome get() = arguments?.getString(ARG_GRUPPO_NOME) ?: ""
    private val topicNome  get() = arguments?.getString(ARG_TOPIC_NOME)  ?: ""

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_checklist, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        adapter = ChecklistAdapter(
            checklistItems,
            ::toggleItem,
            ::apriInformazioniProdotto,
            ::apriYuka
        )
        view.findViewById<RecyclerView>(R.id.rvChecklist).apply {
            layoutManager = LinearLayoutManager(requireContext())
            adapter = this@ChecklistSheet.adapter
        }
        val tvTitolo = view.findViewById<android.widget.TextView>(R.id.tvChecklistTitolo)
        val contesto = listOfNotNull(
            gruppoNome.ifEmpty { null },
            topicNome.ifEmpty { null }
        ).joinToString(" • ")
        if (contesto.isNotEmpty()) tvTitolo.text = "📋 Articoli suggeriti  •  $contesto"
        caricaChecklist()
    }

    private fun caricaChecklist() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getChecklist(gruppoId, topicId, userId) }
            }
            result.onSuccess { adapter.aggiorna(it) }
                  .onFailure { e -> Toast.makeText(requireContext(), "Checklist: ${e.message}", Toast.LENGTH_LONG).show() }
        }
    }

    private fun toggleItem(item: ChecklistItem) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    ApiClient.toggleChecklistItem(
                        gruppoId,
                        topicId,
                        item.nome,
                        item.inLista,
                        userId,
                        item.gtin.ifBlank { null }
                    )
                }
            }
            result.onSuccess {
                onItemChanged?.invoke()
                caricaChecklist()
            }.onFailure {
                Toast.makeText(requireContext(), "Errore", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun apriInformazioniProdotto(item: ChecklistItem) {
        if (item.gtin.isBlank()) return
        lifecycleScope.launch {
            val preview = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getProductPreview(item.gtin) }.getOrNull()
            }
            if (preview == null) {
                Toast.makeText(requireContext(), R.string.prodotto_non_trovato, Toast.LENGTH_LONG).show()
                return@launch
            }
            mostraInformazioniProdotto(preview)
        }
    }

    private fun mostraInformazioniProdotto(preview: ApiClient.ProductPreview) {
        val format = NumberFormat.getNumberInstance(Locale.ITALY).apply { maximumFractionDigits = 1 }
        val nutrienti = buildList {
            preview.energyKcal100g?.let { add("${format.format(it)} kcal") }
            preview.sugars100g?.let { add("zuccheri ${format.format(it)} g") }
            preview.saturatedFat100g?.let { add("saturi ${format.format(it)} g") }
            preview.salt100g?.let { add("sale ${format.format(it)} g") }
        }
        val message = buildString {
            append("Open Food Facts")
            if (preview.nutriscoreGrade.isNotBlank()) append(" · Nutri-Score ${preview.nutriscoreGrade.uppercase()}")
            if (nutrienti.isNotEmpty()) append("\nPer 100 g: ${nutrienti.joinToString(" · ")}")
            preview.novaGroup?.let { append("\nGruppo NOVA $it") }
            if (preview.ingredientsText.isNotBlank()) append("\nIngredienti: ${preview.ingredientsText}")
        }
        android.app.AlertDialog.Builder(requireContext())
            .setTitle(preview.displayName.ifBlank { getString(R.string.informazioni_prodotto) })
            .setMessage(message)
            .setNeutralButton("Aggiorna") { _, _ -> aggiornaInformazioniProdotto(preview.barcode) }
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun aggiornaInformazioniProdotto(gtin: String) {
        lifecycleScope.launch {
            val preview = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getProductPreview(gtin, forceRefresh = true) }.getOrNull()
            }
            if (preview == null) {
                Toast.makeText(requireContext(), R.string.prodotto_non_trovato, Toast.LENGTH_LONG).show()
            } else {
                mostraInformazioniProdotto(preview)
            }
        }
    }

    private fun apriYuka(item: ChecklistItem) {
        if (item.yukaUrl.isBlank()) return
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(item.yukaUrl))) }
            .onFailure { Toast.makeText(requireContext(), R.string.link_non_disponibile, Toast.LENGTH_SHORT).show() }
    }

    fun setOnItemChangedListener(listener: () -> Unit) {
        onItemChanged = listener
    }

    companion object {
        private const val ARG_GRUPPO_ID   = "gruppo_id"
        private const val ARG_TOPIC_ID    = "topic_id"
        private const val ARG_USER_ID     = "user_id"
        private const val ARG_GRUPPO_NOME = "gruppo_nome"
        private const val ARG_TOPIC_NOME  = "topic_nome"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int, gruppoNome: String = "", topicNome: String = "") =
            ChecklistSheet().apply {
                arguments = Bundle().apply {
                    putInt(ARG_GRUPPO_ID, gruppoId)
                    putInt(ARG_TOPIC_ID,  topicId)
                    putInt(ARG_USER_ID,   userId)
                    putString(ARG_GRUPPO_NOME, gruppoNome)
                    putString(ARG_TOPIC_NOME,  topicNome)
                }
            }
    }
}
