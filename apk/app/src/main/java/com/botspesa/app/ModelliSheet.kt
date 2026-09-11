package com.botspesa.app

import android.app.AlertDialog
import android.os.Bundle
import android.view.LayoutInflater
import android.widget.PopupMenu
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

class ModelliSheet : BottomSheetDialogFragment() {

    private var onModelChanged: (() -> Unit)? = null
    private var onModelShared: ((ApiClient.Modello) -> Unit)? = null
    private val gruppoId get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val topicId get() = arguments?.getInt(ARG_TOPIC_ID) ?: 0
    private val userId get() = arguments?.getInt(ARG_USER_ID) ?: 0

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_modelli, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        caricaModelli(view)
        view.findViewById<View>(R.id.btnNuovoModello).setOnClickListener { apriCreazione() }
    }

    private fun apriCreazione() {
        ModelloEditSheet.newInstance(gruppoId, topicId, userId, modello = null)
            .also { it.setOnSavedListener {
                onModelChanged?.invoke()
                view?.let(::caricaModelli)
            } }
            .show(parentFragmentManager, "modello_edit")
    }

    private fun caricaModelli(view: View) {
        val recycler = view.findViewById<RecyclerView>(R.id.rvModelli)
        val empty = view.findViewById<TextView>(R.id.tvModelliVuoto)
        recycler.layoutManager = LinearLayoutManager(requireContext())
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getModelli(gruppoId, topicId, userId) }
            }
            result.onSuccess { modelli ->
                empty.visibility = if (modelli.isEmpty()) View.VISIBLE else View.GONE
                recycler.visibility = if (modelli.isEmpty()) View.GONE else View.VISIBLE
                recycler.adapter = ModelliAdapter(
                    modelli,
                    ::richiama,
                    ::apriModifica,
                    ::confermaEliminazione,
                    { modello -> onModelShared?.invoke(modello) }
                )
            }.onFailure {
                empty.visibility = View.VISIBLE
                empty.text = it.message ?: "Impossibile caricare i modelli"
                recycler.visibility = View.GONE
            }
        }
    }

    private fun richiama(modello: ApiClient.Modello) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.richiamaModello(modello.id, gruppoId, topicId, userId) }
            }
            result.onSuccess { ids ->
                if (ids.isEmpty()) {
                    Toast.makeText(requireContext(), "Nessun articolo inserito", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(requireContext(), "Modello inserito nel topic corrente", Toast.LENGTH_SHORT).show()
                    onModelChanged?.invoke()
                    dismiss()
                }
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Errore inserimento modello", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun apriModifica(modello: ApiClient.Modello) {
        ModelloEditSheet.newInstance(gruppoId, topicId, userId, modello)
            .also { it.setOnSavedListener {
                onModelChanged?.invoke()
                view?.let(::caricaModelli)
            } }
            .show(parentFragmentManager, "modello_edit")
    }

    private fun confermaEliminazione(modello: ApiClient.Modello) {
        AlertDialog.Builder(requireContext())
            .setTitle("Elimina modello")
            .setMessage("Eliminare definitivamente il modello \"${modello.nome}\"?")
            .setNegativeButton("Annulla", null)
            .setPositiveButton("Elimina") { _, _ -> elimina(modello) }
            .show()
    }

    private fun elimina(modello: ApiClient.Modello) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { ApiClient.deleteModello(modello.id, userId) }.getOrDefault(false)
            }
            if (ok) {
                onModelChanged?.invoke()
                view?.let(::caricaModelli)
                Toast.makeText(requireContext(), "Modello eliminato", Toast.LENGTH_SHORT).show()
            } else {
                Toast.makeText(requireContext(), "Eliminazione modello non riuscita", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun setOnModelChangedListener(listener: () -> Unit) {
        onModelChanged = listener
    }

    fun setOnModelSharedListener(listener: (ApiClient.Modello) -> Unit) {
        onModelShared = listener
    }

    companion object {
        private const val ARG_GRUPPO_ID = "gruppo_id"
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_USER_ID = "user_id"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int) = ModelliSheet().apply {
            arguments = Bundle().apply {
                putInt(ARG_GRUPPO_ID, gruppoId)
                putInt(ARG_TOPIC_ID, topicId)
                putInt(ARG_USER_ID, userId)
            }
        }
    }
}

private class ModelliAdapter(
    private val modelli: List<ApiClient.Modello>,
    private val onRecall: (ApiClient.Modello) -> Unit,
    private val onEdit: (ApiClient.Modello) -> Unit,
    private val onDelete: (ApiClient.Modello) -> Unit,
    private val onShare: (ApiClient.Modello) -> Unit
) : RecyclerView.Adapter<ModelliAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val nome: TextView = view.findViewById(R.id.tvModelloNome)
        val articoli: TextView = view.findViewById(R.id.tvModelloArticoli)
        val share: View = view.findViewById(R.id.ivModelloShare)
        val aggiungi: TextView = view.findViewById(R.id.btnModelloAggiungi)
        val modifica: TextView = view.findViewById(R.id.btnModelloModifica)
        val elimina: TextView = view.findViewById(R.id.btnModelloElimina)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder = ViewHolder(
        LayoutInflater.from(parent.context).inflate(R.layout.item_modello, parent, false)
    )

    override fun getItemCount(): Int = modelli.size

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val modello = modelli[position]
        holder.nome.text = modello.nome
        holder.articoli.text = modello.items.joinToString(", ")
        holder.itemView.setOnClickListener { onRecall(modello) }
        holder.itemView.setOnLongClickListener { anchor ->
            PopupMenu(anchor.context, anchor).apply {
                menu.add("Condividi items modello")
                setOnMenuItemClickListener {
                    onShare(modello)
                    true
                }
                show()
            }
            true
        }
        holder.share.setOnClickListener { onShare(modello) }
        holder.aggiungi.setOnClickListener { onRecall(modello) }
        holder.modifica.setOnClickListener { onEdit(modello) }
        holder.elimina.setOnClickListener { onDelete(modello) }
    }
}
