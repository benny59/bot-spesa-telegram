package com.botspesa.app

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class GestioneCarteSheet : BottomSheetDialogFragment() {

    private val gruppoId get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val userId   get() = arguments?.getInt(ARG_USER_ID)   ?: 0
    private val gruppoNome get() = arguments?.getString(ARG_GRUPPO_NOME) ?: ""

    private lateinit var rvMieCarte: RecyclerView
    private lateinit var rvCondivisioni: RecyclerView
    private lateinit var tvNessuna: TextView
    private lateinit var tvTitoloCondivisioni: TextView
    private lateinit var dividerCondivisioni: View
    private var carte = mutableListOf<CartaFedeltaItem>()

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_gestione_carte, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        rvMieCarte          = view.findViewById(R.id.rvMieCarte)
        rvCondivisioni      = view.findViewById(R.id.rvCondivisioni)
        tvNessuna           = view.findViewById(R.id.tvNessunaCartaMia)
        tvTitoloCondivisioni = view.findViewById(R.id.tvTitoloCondivisioni)
        dividerCondivisioni  = view.findViewById(R.id.dividerCondivisioni)

        rvMieCarte.layoutManager     = LinearLayoutManager(requireContext())
        rvCondivisioni.layoutManager = LinearLayoutManager(requireContext())

        if (gruppoId != 0) {
            tvTitoloCondivisioni.visibility = View.VISIBLE
            tvTitoloCondivisioni.text = "CONDIVISIONE CON $gruppoNome"
            dividerCondivisioni.visibility = View.VISIBLE
            rvCondivisioni.visibility = View.VISIBLE
        }

        view.findViewById<Button>(R.id.btnAggiungiCarta).setOnClickListener { mostraDialogAggiunta() }
        caricaCarte()
    }

    private fun caricaCarte() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getMieCarte(userId, gruppoId) }
            }
            result.onSuccess { lista ->
                carte.clear()
                carte.addAll(lista)
                aggiornaViste()
            }.onFailure {
                Toast.makeText(requireContext(), "Errore: ${it.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun aggiornaViste() {
        tvNessuna.visibility = if (carte.isEmpty()) View.VISIBLE else View.GONE

        // Adapter per "Le mie carte" — bottone condividi nascosto
        rvMieCarte.adapter = CartaMiaAdapter(carte, showCondividi = false,
            onElimina  = { carta -> confermaElimina(carta) },
            onCondividi = { _, _ -> })

        // Adapter per condivisioni — bottone condividi visibile, elimina nascosto
        if (gruppoId != 0) {
            rvCondivisioni.adapter = CartaMiaAdapter(carte, showCondividi = true,
                onElimina  = { _ -> },
                onCondividi = { carta, condivisa -> toggleCondivisione(carta, condivisa) })
        }
    }

    private fun toggleCondivisione(carta: CartaFedeltaItem, eraCondivisa: Boolean) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    if (eraCondivisa) ApiClient.scollegaCarta(carta.id, gruppoId)
                    else             ApiClient.collegaCarta(carta.id, gruppoId, userId)
                }.getOrDefault(false)
            }
            if (ok) caricaCarte()
            else Toast.makeText(requireContext(), "Errore condivisione", Toast.LENGTH_SHORT).show()
        }
    }

    private fun confermaElimina(carta: CartaFedeltaItem) {
        AlertDialog.Builder(requireContext())
            .setTitle("Elimina carta")
            .setMessage("Eliminare \"${carta.nome}\"? Verrà rimossa da tutti i gruppi.")
            .setPositiveButton("Elimina") { _, _ ->
                lifecycleScope.launch {
                    val ok = withContext(Dispatchers.IO) {
                        runCatching { ApiClient.eliminaCarta(carta.id, userId) }.getOrDefault(false)
                    }
                    if (ok) caricaCarte()
                    else Toast.makeText(requireContext(), "Errore eliminazione", Toast.LENGTH_SHORT).show()
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun mostraDialogAggiunta() {
        val dp = resources.displayMetrics.density
        val layout = android.widget.LinearLayout(requireContext()).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding((24 * dp).toInt(), (8 * dp).toInt(), (24 * dp).toInt(), 0)
        }
        val etNome   = EditText(requireContext()).apply { hint = "Nome carta (es. Coop)" }
        val etCodice = EditText(requireContext()).apply {
            hint = "Codice (numerico o alfanumerico)"
            inputType = android.text.InputType.TYPE_CLASS_TEXT
        }
        layout.addView(etNome)
        layout.addView(etCodice)

        AlertDialog.Builder(requireContext())
            .setTitle("Aggiungi carta fedeltà")
            .setView(layout)
            .setPositiveButton("Salva", null)
            .setNegativeButton("Annulla", null)
            .create()
            .also { dlg ->
                dlg.setOnShowListener {
                    dlg.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                        val nome   = etNome.text.toString().trim()
                        val codice = etCodice.text.toString().trim()
                        if (nome.isEmpty())   { etNome.error   = "Obbligatorio"; return@setOnClickListener }
                        if (codice.isEmpty()) { etCodice.error = "Obbligatorio"; return@setOnClickListener }
                        dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = false
                        lifecycleScope.launch {
                            val ok = withContext(Dispatchers.IO) {
                                runCatching { ApiClient.creaCarta(userId, nome, codice) }.getOrDefault(false)
                            }
                            if (ok) { dlg.dismiss(); caricaCarte() }
                            else {
                                dlg.getButton(AlertDialog.BUTTON_POSITIVE).isEnabled = true
                                Toast.makeText(requireContext(), "Errore salvataggio", Toast.LENGTH_SHORT).show()
                            }
                        }
                    }
                }
            }
            .show()
    }

    companion object {
        private const val ARG_GRUPPO_ID   = "gruppo_id"
        private const val ARG_USER_ID     = "user_id"
        private const val ARG_GRUPPO_NOME = "gruppo_nome"

        fun newInstance(gruppoId: Int, userId: Int, gruppoNome: String = "") =
            GestioneCarteSheet().apply {
                arguments = Bundle().apply {
                    putInt(ARG_GRUPPO_ID, gruppoId)
                    putInt(ARG_USER_ID,   userId)
                    putString(ARG_GRUPPO_NOME, gruppoNome.uppercase())
                }
            }
    }
}

private class CartaMiaAdapter(
    private val carte: List<CartaFedeltaItem>,
    private val showCondividi: Boolean,
    private val onElimina:  (CartaFedeltaItem) -> Unit,
    private val onCondividi: (CartaFedeltaItem, Boolean) -> Unit
) : RecyclerView.Adapter<CartaMiaAdapter.VH>() {

    inner class VH(v: View) : RecyclerView.ViewHolder(v) {
        val tvNome:     TextView    = v.findViewById(R.id.tvNomeCartaMia)
        val btnCond:    Button      = v.findViewById(R.id.btnCondividi)
        val btnElimina: ImageButton = v.findViewById(R.id.btnElimina)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        VH(LayoutInflater.from(parent.context).inflate(R.layout.item_carta_mia, parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) {
        val carta = carte[position]
        holder.tvNome.text = carta.nome

        if (showCondividi) {
            holder.btnElimina.visibility = View.GONE
            holder.btnCond.visibility    = View.VISIBLE
            if (carta.condivisaConGruppo) {
                holder.btnCond.text = "✓ Condivisa"
                holder.btnCond.setOnClickListener { onCondividi(carta, true) }
            } else {
                holder.btnCond.text = "Condividi"
                holder.btnCond.setOnClickListener { onCondividi(carta, false) }
            }
        } else {
            holder.btnElimina.visibility = View.VISIBLE
            holder.btnCond.visibility    = View.GONE
            holder.btnElimina.setOnClickListener { onElimina(carta) }
            // Tap sul nome → visualizza il barcode
            holder.tvNome.setOnClickListener {
                holder.tvNome.context.startActivity(
                    android.content.Intent(holder.tvNome.context, BarcodeActivity::class.java).apply {
                        putExtra(BarcodeActivity.EXTRA_NOME,   carta.nome)
                        putExtra(BarcodeActivity.EXTRA_CODICE, carta.codice)
                        putExtra(BarcodeActivity.EXTRA_FORMATO, carta.formato)
                    }
                )
            }
        }
    }

    override fun getItemCount() = carte.size
}
