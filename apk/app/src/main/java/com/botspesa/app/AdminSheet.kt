package com.botspesa.app

import android.app.AlertDialog
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import com.google.android.material.button.MaterialButton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class AdminSheet : BottomSheetDialogFragment() {

    companion object {
        fun newInstance(userId: Int) = AdminSheet().apply {
            arguments = Bundle().also { it.putInt("user_id", userId) }
        }
    }

    private val userId get() = arguments?.getInt("user_id") ?: 0

    private lateinit var rvPending: RecyclerView
    private lateinit var tvNoPending: TextView
    private lateinit var tvPendingCount: TextView
    private lateinit var rvUtenti: RecyclerView
    private lateinit var spinnerLingua: Spinner

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_admin_sheet, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        (dialog as? BottomSheetDialog)?.behavior?.state = BottomSheetBehavior.STATE_EXPANDED

        rvPending      = view.findViewById(R.id.rvPending)
        tvNoPending    = view.findViewById(R.id.tvNoPending)
        tvPendingCount = view.findViewById(R.id.tvPendingCount)
        rvUtenti       = view.findViewById(R.id.rvUtenti)
        spinnerLingua  = view.findViewById(R.id.spinnerLingua)

        val opzioni = LocalizationManager.supportedLanguages().map { it.label }
        val adapter = ArrayAdapter(requireContext(), android.R.layout.simple_spinner_item, opzioni)
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
        spinnerLingua.adapter = adapter

        val currentLanguage = LocalizationManager.currentLanguageCode(requireContext())
        val currentIndex = LocalizationManager.supportedLanguages().indexOfFirst { it.code == currentLanguage }
        if (currentIndex >= 0) spinnerLingua.setSelection(currentIndex)

        spinnerLingua.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val selected = LocalizationManager.supportedLanguages()[position].code
                if (selected != currentLanguage) {
                    LocalizationManager.applyLanguage(requireContext(), selected)
                    requireActivity().recreate()
                }
            }

            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }

        rvPending.isNestedScrollingEnabled = false
        rvUtenti.isNestedScrollingEnabled  = false
        rvPending.layoutManager = LinearLayoutManager(requireContext())
        rvUtenti.layoutManager  = LinearLayoutManager(requireContext())

        caricaDati()
    }

    private fun caricaDati() {
        lifecycleScope.launch {
            val pending = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getAdminPending(userId) }.getOrDefault(emptyList())
            }
            val utenti = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getAdminUtenti(userId) }.getOrDefault(emptyList())
            }

            tvPendingCount.text = "Richieste in sospeso (${pending.size})"
            if (pending.isEmpty()) {
                tvNoPending.visibility = View.VISIBLE
                rvPending.visibility   = View.GONE
            } else {
                tvNoPending.visibility = View.GONE
                rvPending.visibility   = View.VISIBLE
                rvPending.adapter = PendingAdapter(pending)
            }
            rvUtenti.adapter = UtentiAdapter(utenti)
        }
    }

    private fun onApprova(utente: ApiClient.PendingUtente) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching { ApiClient.approvaUtente(userId, utente.userId) }.getOrDefault(false)
            }
            if (ok) {
                Toast.makeText(requireContext(), "✅ ${utente.fullName} approvato", Toast.LENGTH_SHORT).show()
                caricaDati()
            } else {
                Toast.makeText(requireContext(), "❌ Errore di rete", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun onRifiuta(utente: ApiClient.PendingUtente) {
        AlertDialog.Builder(requireContext())
            .setTitle("Rifiuta richiesta")
            .setMessage("Rifiutare l'accesso a ${utente.fullName.ifEmpty { utente.userId.toString() }}?")
            .setPositiveButton("Rifiuta") { _, _ ->
                lifecycleScope.launch {
                    val ok = withContext(Dispatchers.IO) {
                        runCatching { ApiClient.rifiutaUtente(userId, utente.userId) }.getOrDefault(false)
                    }
                    if (ok) {
                        Toast.makeText(requireContext(), "Richiesta rifiutata", Toast.LENGTH_SHORT).show()
                        caricaDati()
                    } else {
                        Toast.makeText(requireContext(), "❌ Errore di rete", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun onRevoca(utente: ApiClient.AdminUtente) {
        AlertDialog.Builder(requireContext())
            .setTitle("Revoca accesso")
            .setMessage("Revocare l'accesso a ${utente.fullName.ifEmpty { utente.userId.toString() }}?")
            .setPositiveButton("Revoca") { _, _ ->
                lifecycleScope.launch {
                    val ok = withContext(Dispatchers.IO) {
                        runCatching { ApiClient.revocaUtente(userId, utente.userId) }.getOrDefault(false)
                    }
                    if (ok) {
                        Toast.makeText(requireContext(), "✅ Accesso revocato", Toast.LENGTH_SHORT).show()
                        caricaDati()
                    } else {
                        Toast.makeText(requireContext(), "❌ Errore di rete", Toast.LENGTH_SHORT).show()
                    }
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    // --- Adapter richieste in sospeso ---

    inner class PendingAdapter(private val items: List<ApiClient.PendingUtente>) :
        RecyclerView.Adapter<PendingAdapter.VH>() {

        inner class VH(v: View) : RecyclerView.ViewHolder(v) {
            val tvNome: TextView       = v.findViewById(R.id.tvNome)
            val tvUsername: TextView   = v.findViewById(R.id.tvUsername)
            val tvData: TextView       = v.findViewById(R.id.tvData)
            val btnApprova: MaterialButton = v.findViewById(R.id.btnApprova)
            val btnRifiuta: MaterialButton = v.findViewById(R.id.btnRifiuta)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            VH(LayoutInflater.from(parent.context).inflate(R.layout.item_pending_utente, parent, false))

        override fun getItemCount() = items.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val u = items[position]
            holder.tvNome.text     = u.fullName.ifEmpty { "ID ${u.userId}" }
            holder.tvUsername.text = if (u.username.isNotEmpty()) "@${u.username}" else ""
            holder.tvData.text     = u.requestedAt.take(10)
            holder.btnApprova.setOnClickListener { onApprova(u) }
            holder.btnRifiuta.setOnClickListener { onRifiuta(u) }
        }
    }

    // --- Adapter utenti autorizzati ---

    inner class UtentiAdapter(private val items: List<ApiClient.AdminUtente>) :
        RecyclerView.Adapter<UtentiAdapter.VH>() {

        inner class VH(v: View) : RecyclerView.ViewHolder(v) {
            val tvNome: TextView       = v.findViewById(R.id.tvNome)
            val tvUsername: TextView   = v.findViewById(R.id.tvUsername)
            val tvData: TextView       = v.findViewById(R.id.tvData)
            val btnRevoca: MaterialButton = v.findViewById(R.id.btnRevoca)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
            VH(LayoutInflater.from(parent.context).inflate(R.layout.item_whitelist_utente, parent, false))

        override fun getItemCount() = items.size

        override fun onBindViewHolder(holder: VH, position: Int) {
            val u = items[position]
            holder.tvNome.text     = buildString {
                if (u.isCreator) append("👑 ")
                append(u.fullName.ifEmpty { "ID ${u.userId}" })
            }
            holder.tvUsername.text = if (u.username.isNotEmpty()) "@${u.username}" else ""
            holder.tvData.text     = "dal ${u.addedAt.take(10)}"
            holder.btnRevoca.isEnabled = !u.isCreator
            holder.btnRevoca.setOnClickListener { onRevoca(u) }
        }
    }
}
