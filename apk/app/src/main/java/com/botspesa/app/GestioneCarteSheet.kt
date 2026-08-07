package com.botspesa.app

import android.app.AlertDialog
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import androidx.recyclerview.widget.GridLayoutManager
import androidx.recyclerview.widget.RecyclerView
import coil.load
import com.google.android.material.bottomsheet.BottomSheetDialogFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

class GestioneCarteSheet : BottomSheetDialogFragment() {

    private val gruppoId   get() = arguments?.getInt(ARG_GRUPPO_ID)      ?: 0
    private val userId     get() = arguments?.getInt(ARG_USER_ID)        ?: 0
    private val gruppoNome get() = arguments?.getString(ARG_GRUPPO_NOME) ?: ""

    private lateinit var rvMieCarte: RecyclerView
    private lateinit var tvNessuna:  TextView
    private var carte = mutableListOf<CartaFedeltaItem>()

    private var immagineSelezionataBytes: ByteArray? = null
    private var onImagePicked: ((android.net.Uri) -> Unit)? = null

    private val pickImage = registerForActivityResult(ActivityResultContracts.GetContent()) { uri ->
        uri ?: return@registerForActivityResult
        val bytes = requireContext().contentResolver.openInputStream(uri)?.use { stream ->
            val bmp = BitmapFactory.decodeStream(stream) ?: return@use null
            val scaled = if (bmp.width > 1200)
                Bitmap.createScaledBitmap(bmp, 1200, 1200 * bmp.height / bmp.width, true)
            else bmp
            ByteArrayOutputStream().also { out -> scaled.compress(Bitmap.CompressFormat.JPEG, 82, out) }.toByteArray()
        }
        immagineSelezionataBytes = bytes
        onImagePicked?.invoke(uri)
    }

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_gestione_carte, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        rvMieCarte = view.findViewById(R.id.rvMieCarte)
        tvNessuna  = view.findViewById(R.id.tvNessunaCartaMia)
        rvMieCarte.layoutManager = GridLayoutManager(requireContext(), 3)

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
        rvMieCarte.adapter = CarteGestioneAdapter(carte, gruppoNome) { carta -> mostraMenuCarta(carta) }
    }

    private fun mostraMenuCarta(carta: CartaFedeltaItem) {
        val voci = buildList {
            add("Visualizza barcode")
            if (gruppoId != 0)
                add(if (carta.condivisaConGruppo) "Rimuovi da $gruppoNome" else "Assegna a $gruppoNome")
            add("Cancella carta")
        }.toTypedArray()

        AlertDialog.Builder(requireContext())
            .setTitle(carta.nome)
            .setItems(voci) { _, which ->
                when (voci[which]) {
                    "Visualizza barcode" -> apriBarcode(carta)
                    "Cancella carta"     -> confermaElimina(carta)
                    else                 -> toggleCondivisione(carta)
                }
            }
            .setNegativeButton("Annulla", null)
            .show()
    }

    private fun apriBarcode(carta: CartaFedeltaItem) {
        startActivity(Intent(requireContext(), BarcodeActivity::class.java).apply {
            putExtra(BarcodeActivity.EXTRA_NOME,         carta.nome)
            putExtra(BarcodeActivity.EXTRA_CODICE,       carta.codice)
            putExtra(BarcodeActivity.EXTRA_FORMATO,      carta.formato)
            putExtra(BarcodeActivity.EXTRA_IMMAGINE_URL, carta.immagineUrl ?: "")
        })
    }

    private fun toggleCondivisione(carta: CartaFedeltaItem) {
        lifecycleScope.launch {
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    if (carta.condivisaConGruppo) ApiClient.scollegaCarta(carta.id, gruppoId)
                    else                          ApiClient.collegaCarta(carta.id, gruppoId, userId)
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
        immagineSelezionataBytes = null
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
        val imgPreview = ImageView(requireContext()).apply {
            layoutParams = android.widget.LinearLayout.LayoutParams(
                android.widget.LinearLayout.LayoutParams.MATCH_PARENT, (120 * dp).toInt()
            ).also { it.topMargin = (8 * dp).toInt() }
            scaleType = ImageView.ScaleType.CENTER_CROP
            visibility = View.GONE
        }
        val btnFoto = Button(requireContext()).apply {
            text = "📷 Aggiungi immagine carta"
            setOnClickListener {
                onImagePicked = { uri ->
                    imgPreview.setImageURI(uri)
                    imgPreview.visibility = View.VISIBLE
                }
                pickImage.launch("image/*")
            }
        }
        layout.addView(etNome)
        layout.addView(etCodice)
        layout.addView(btnFoto)
        layout.addView(imgPreview)

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
                                runCatching { ApiClient.creaCarta(userId, nome, codice, immagineSelezionataBytes) }
                                    .getOrDefault(false)
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

private class CarteGestioneAdapter(
    private val carte: List<CartaFedeltaItem>,
    private val gruppoNome: String,
    private val onTap: (CartaFedeltaItem) -> Unit
) : RecyclerView.Adapter<CarteGestioneAdapter.VH>() {

    inner class VH(v: View) : RecyclerView.ViewHolder(v) {
        val tvNome:      TextView  = v.findViewById(R.id.tvNomeCartaGest)
        val imgCarta:    ImageView = v.findViewById(R.id.imgCarta)
        val viewOverlay: View      = v.findViewById(R.id.viewNomeOverlay)
        val tvBadge:     TextView  = v.findViewById(R.id.tvBadgeCondivisa)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int) =
        VH(LayoutInflater.from(parent.context).inflate(R.layout.item_carta_gestione, parent, false))

    override fun onBindViewHolder(holder: VH, position: Int) {
        val carta = carte[position]
        holder.tvNome.text = carta.nome

        if (!carta.immagineUrl.isNullOrEmpty()) {
            holder.imgCarta.visibility    = View.VISIBLE
            holder.viewOverlay.visibility = View.VISIBLE
            holder.tvNome.setTextColor(android.graphics.Color.WHITE)
            holder.tvNome.gravity = android.view.Gravity.BOTTOM or android.view.Gravity.CENTER_HORIZONTAL
            holder.imgCarta.load(carta.immagineUrl)
        } else {
            holder.imgCarta.visibility    = View.GONE
            holder.viewOverlay.visibility = View.GONE
            holder.tvNome.setTextColor(holder.tvNome.context.getColor(R.color.text_primary))
            holder.tvNome.gravity = android.view.Gravity.CENTER
        }

        holder.tvBadge.visibility = if (carta.condivisaConGruppo && gruppoNome.isNotEmpty())
            View.VISIBLE else View.GONE

        holder.itemView.setOnClickListener { onTap(carta) }
    }

    override fun getItemCount() = carte.size
}
