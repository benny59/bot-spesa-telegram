package com.botspesa.app

import android.os.Bundle
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Schermata dedicata al CRUD di un singolo modello: rinomina, aggiunta/rimozione e riordino (drag & drop) degli articoli.
class ModelloEditSheet : BottomSheetDialogFragment() {

    private var onSaved: (() -> Unit)? = null
    private val gruppoId get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val topicId get() = arguments?.getInt(ARG_TOPIC_ID) ?: 0
    private val userId get() = arguments?.getInt(ARG_USER_ID) ?: 0
    private val modelloId get() = arguments?.getInt(ARG_MODELLO_ID) ?: 0
    private val isNuovo get() = modelloId <= 0
    private val nomeIniziale get() = arguments?.getString(ARG_NOME).orEmpty()
    private val itemsIniziali get() = arguments?.getStringArrayList(ARG_ITEMS)?.toList() ?: emptyList()

    private val items = mutableListOf<String>()
    private lateinit var adapter: ModelloEditAdapter

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_modello_edit, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        items.clear()
        items.addAll(itemsIniziali)

        view.findViewById<TextView>(R.id.tvTitoloModelloEdit).text = if (isNuovo) "Nuovo modello" else "Modifica modello"
        val etNome = view.findViewById<EditText>(R.id.etModelloNome)
        val etNuovoItem = view.findViewById<EditText>(R.id.etNuovoItem)
        val recycler = view.findViewById<RecyclerView>(R.id.rvModelloItems)
        etNome.setText(nomeIniziale)

        adapter = ModelloEditAdapter(items) { pos -> adapter.notifyItemRemoved(pos) }
        recycler.layoutManager = LinearLayoutManager(requireContext())
        recycler.adapter = adapter

        val touchHelper = ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN, 0
        ) {
            override fun onMove(rv: RecyclerView, vh: RecyclerView.ViewHolder, target: RecyclerView.ViewHolder): Boolean {
                val from = vh.adapterPosition
                val to = target.adapterPosition
                if (from == RecyclerView.NO_POSITION || to == RecyclerView.NO_POSITION) return false
                items.add(to, items.removeAt(from))
                adapter.notifyItemMoved(from, to)
                return true
            }

            override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {}
        })
        touchHelper.attachToRecyclerView(recycler)
        adapter.onStartDrag = { holder -> touchHelper.startDrag(holder) }

        view.findViewById<TextView>(R.id.btnAggiungiItem).setOnClickListener {
            val nuovo = etNuovoItem.text.toString().trim()
            if (nuovo.isEmpty()) return@setOnClickListener
            items.add(nuovo)
            adapter.notifyItemInserted(items.size - 1)
            etNuovoItem.text.clear()
        }

        view.findViewById<TextView>(R.id.btnAnnullaModifica).setOnClickListener { dismiss() }
        view.findViewById<TextView>(R.id.btnSalvaModifica).setOnClickListener {
            salva(etNome.text.toString().trim())
        }
    }

    private fun salva(nome: String) {
        if (nome.isEmpty()) {
            Toast.makeText(requireContext(), "Inserisci un nome modello", Toast.LENGTH_SHORT).show()
            return
        }
        if (items.isEmpty()) {
            Toast.makeText(requireContext(), "Il modello deve avere almeno un articolo", Toast.LENGTH_SHORT).show()
            return
        }
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    if (isNuovo) ApiClient.createModello(gruppoId, topicId, userId, nome, items)
                    else ApiClient.updateModello(modelloId, userId, nome, items)
                }.getOrDefault(false)
            }
            if (ok) {
                Toast.makeText(requireContext(), if (isNuovo) "Modello creato" else "Modello aggiornato", Toast.LENGTH_SHORT).show()
                onSaved?.invoke()
                dismiss()
            } else {
                Toast.makeText(requireContext(), "Impossibile salvare il modello", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun setOnSavedListener(listener: () -> Unit) {
        onSaved = listener
    }

    companion object {
        private const val ARG_GRUPPO_ID = "gruppo_id"
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_USER_ID = "user_id"
        private const val ARG_MODELLO_ID = "modello_id"
        private const val ARG_NOME = "nome"
        private const val ARG_ITEMS = "items"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int, modello: ApiClient.Modello?) = ModelloEditSheet().apply {
            arguments = Bundle().apply {
                putInt(ARG_GRUPPO_ID, gruppoId)
                putInt(ARG_TOPIC_ID, topicId)
                putInt(ARG_USER_ID, userId)
                putInt(ARG_MODELLO_ID, modello?.id ?: 0)
                putString(ARG_NOME, modello?.nome.orEmpty())
                putStringArrayList(ARG_ITEMS, ArrayList(modello?.items.orEmpty()))
            }
        }
    }
}

private class ModelloEditAdapter(
    private val items: MutableList<String>,
    private val onRemoved: (Int) -> Unit
) : RecyclerView.Adapter<ModelloEditAdapter.ViewHolder>() {

    var onStartDrag: ((RecyclerView.ViewHolder) -> Unit)? = null

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val nome: TextView = view.findViewById(R.id.tvNomeItemModifica)
        val rimuovi: TextView = view.findViewById(R.id.tvRimuoviItemModifica)
        val handle: TextView = view.findViewById(R.id.tvDragHandle)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder = ViewHolder(
        LayoutInflater.from(parent.context).inflate(R.layout.item_modello_edit_row, parent, false)
    )

    override fun getItemCount(): Int = items.size

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        holder.nome.text = items[position]
        holder.rimuovi.setOnClickListener {
            val pos = holder.adapterPosition
            if (pos == RecyclerView.NO_POSITION) return@setOnClickListener
            items.removeAt(pos)
            onRemoved(pos)
        }
        holder.handle.setOnTouchListener { _, event ->
            if (event.actionMasked == MotionEvent.ACTION_DOWN) onStartDrag?.invoke(holder)
            false
        }
    }
}
