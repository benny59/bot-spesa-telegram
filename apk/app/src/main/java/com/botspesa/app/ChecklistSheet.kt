package com.botspesa.app

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
        adapter = ChecklistAdapter(checklistItems) { item -> toggleItem(item) }
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
                runCatching { ApiClient.getChecklist(gruppoId, topicId) }
            }
            result.onSuccess { adapter.aggiorna(it) }
                  .onFailure { e -> Toast.makeText(requireContext(), "Checklist: ${e.message}", Toast.LENGTH_LONG).show() }
        }
    }

    private fun toggleItem(item: ChecklistItem) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.toggleChecklistItem(gruppoId, topicId, item.nome, item.inLista, userId) }
            }
            result.onSuccess {
                onItemChanged?.invoke()
                caricaChecklist()
            }.onFailure {
                Toast.makeText(requireContext(), "Errore", Toast.LENGTH_SHORT).show()
            }
        }
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
