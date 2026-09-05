package com.botspesa.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class CarteSheet : BottomSheetDialogFragment() {

    companion object {
        fun newInstance(gruppoId: Int, userId: Int) = CarteSheet().apply {
            arguments = Bundle().also {
                it.putInt("gruppo_id", gruppoId)
                it.putInt("user_id", userId)
            }
        }
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_carte_sheet, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val gruppoId = arguments?.getInt("gruppo_id") ?: 1
        val userId = arguments?.getInt("user_id") ?: 0
        val recycler = view.findViewById<RecyclerView>(R.id.recyclerCarte)
        recycler.layoutManager = GridLayoutManager(requireContext(), 3)

        viewLifecycleOwner.lifecycleScope.launch {
            val carte = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getCarte(gruppoId, userId) }.getOrDefault(emptyList())
            }
            recycler.adapter = CarteAdapter(carte) { carta ->
                dismiss()
                startActivity(Intent(requireContext(), BarcodeActivity::class.java).apply {
                    putExtra(BarcodeActivity.EXTRA_NOME, carta.nome)
                    putExtra(BarcodeActivity.EXTRA_CODICE, carta.codice)
                    putExtra(BarcodeActivity.EXTRA_FORMATO, carta.formato)
                })
            }
        }
    }
}

class CarteAdapter(
    private val carte: List<CartaFedeltaItem>,
    private val onClick: (CartaFedeltaItem) -> Unit
) : RecyclerView.Adapter<CarteAdapter.ViewHolder>() {

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvNome: TextView = view.findViewById(R.id.tvNomeCarta)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder =
        ViewHolder(LayoutInflater.from(parent.context).inflate(R.layout.item_carta, parent, false))

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val carta = carte[position]
        val (marker, color) = carta.statusMarker()

        holder.tvNome.text = "$marker ${carta.nome}"
        holder.tvNome.setTextColor(color)
        holder.itemView.setOnClickListener { onClick(carta) }
    }

    override fun getItemCount() = carte.size
}
