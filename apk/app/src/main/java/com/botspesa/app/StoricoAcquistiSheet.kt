package com.botspesa.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class StoricoAcquistiSheet : BottomSheetDialogFragment() {

    private var onItemChanged: (() -> Unit)? = null

    private val gruppoId   get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val topicId    get() = arguments?.getInt(ARG_TOPIC_ID) ?: 0
    private val userId     get() = arguments?.getInt(ARG_USER_ID) ?: 0
    private val gruppoNome get() = arguments?.getString(ARG_GRUPPO_NOME).orEmpty()
    private val topicNome  get() = arguments?.getString(ARG_TOPIC_NOME).orEmpty()

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View = inflater.inflate(R.layout.fragment_storico_acquisti, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val titolo = view.findViewById<TextView>(R.id.tvStoricoTitolo)
        val contesto = listOf(gruppoNome, topicNome).filter { it.isNotEmpty() }.joinToString(" • ")
        if (contesto.isNotEmpty()) titolo.text = "🕒 Storico acquisti  •  $contesto"

        val recycler = view.findViewById<RecyclerView>(R.id.rvStoricoAcquisti)
        val vuoto = view.findViewById<TextView>(R.id.tvStoricoVuoto)
        recycler.layoutManager = LinearLayoutManager(requireContext())

        caricaStorico(recycler, vuoto)
    }

    private fun caricaStorico(recycler: RecyclerView, vuoto: TextView) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getStoricoAcquisti(gruppoId, topicId) }
            }
            result.onSuccess { acquisti ->
                vuoto.visibility = if (acquisti.isEmpty()) View.VISIBLE else View.GONE
                recycler.visibility = if (acquisti.isEmpty()) View.GONE else View.VISIBLE
                recycler.adapter = StoricoAdapter(acquisti) { acquisto -> toggleItem(acquisto, recycler, vuoto) }
            }.onFailure { errore ->
                Toast.makeText(requireContext(), "Storico: ${errore.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun toggleItem(acquisto: ApiClient.StoricoAcquisto, recycler: RecyclerView, vuoto: TextView) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.toggleChecklistItem(gruppoId, topicId, acquisto.nome, acquisto.inLista, userId) }
            }
            result.onSuccess {
                onItemChanged?.invoke()
                caricaStorico(recycler, vuoto)
            }.onFailure {
                Toast.makeText(requireContext(), "Errore", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun setOnItemChangedListener(listener: () -> Unit) {
        onItemChanged = listener
    }

    private class StoricoAdapter(
        private val acquisti: List<ApiClient.StoricoAcquisto>,
        private val onToggle: (ApiClient.StoricoAcquisto) -> Unit
    ) :
        RecyclerView.Adapter<StoricoAdapter.ViewHolder>() {

        class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val stato: TextView = view.findViewById(R.id.tvStoricoStatus)
            val nome: TextView = view.findViewById(R.id.tvStoricoNome)
            val data: TextView = view.findViewById(R.id.tvStoricoData)
            val inseritoDa: TextView = view.findViewById(R.id.tvStoricoInseritoDa)
            val acquistatoDa: TextView = view.findViewById(R.id.tvStoricoAcquistatoDa)
            val conteggio: TextView = view.findViewById(R.id.tvStoricoConteggio)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_storico_acquisto, parent, false)
            return ViewHolder(view)
        }

        override fun getItemCount(): Int = acquisti.size

        override fun onBindViewHolder(holder: ViewHolder, position: Int) {
            val acquisto = acquisti[position]
            holder.nome.text = acquisto.nomeDisplay
            holder.data.text = formattaData(acquisto.updatedAt)
            holder.inseritoDa.visibility = if (acquisto.creatore.isEmpty()) View.GONE else View.VISIBLE
            holder.inseritoDa.text = "↳ ${acquisto.creatore}"
            holder.acquistatoDa.visibility = if (acquisto.acquirente.isEmpty()) View.GONE else View.VISIBLE
            holder.acquistatoDa.text = "↗ ${acquisto.acquirente}"

            val categoria = if (acquisto.categoriaNome.isNotEmpty()) {
                val visualizzata = if (acquisto.categoriaEffimera) acquisto.categoriaNome.lowercase() else acquisto.categoriaNome
                val tradotta = LocalizationManager.localizedCategoryName(holder.itemView.context, visualizzata)
                "${if (acquisto.categoriaEffimera) "◌" else "▣"} $tradotta"
            } else ""
            holder.conteggio.text = listOf(categoria, "${acquisto.conteggio} volte")
                .filter { it.isNotEmpty() }
                .joinToString(" • ")

            if (acquisto.inLista) {
                holder.stato.text = "✓"
                holder.stato.setBackgroundResource(R.drawable.circle_initials_green)
            } else {
                holder.stato.text = "+"
                holder.stato.setBackgroundResource(R.drawable.circle_initials)
            }

            holder.itemView.setOnClickListener { onToggle(acquisto) }
        }

        private fun formattaData(value: String): String = runCatching {
            LocalDateTime.parse(value, DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"))
                .format(DateTimeFormatter.ofPattern("dd/MM/yyyy HH:mm"))
        }.getOrDefault(value)
    }

    companion object {
        private const val ARG_GRUPPO_ID = "gruppo_id"
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_USER_ID = "user_id"
        private const val ARG_GRUPPO_NOME = "gruppo_nome"
        private const val ARG_TOPIC_NOME = "topic_nome"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int, gruppoNome: String, topicNome: String) =
            StoricoAcquistiSheet().apply {
                arguments = Bundle().apply {
                    putInt(ARG_GRUPPO_ID, gruppoId)
                    putInt(ARG_TOPIC_ID, topicId)
                    putInt(ARG_USER_ID, userId)
                    putString(ARG_GRUPPO_NOME, gruppoNome)
                    putString(ARG_TOPIC_NOME, topicNome)
                }
            }
    }
}