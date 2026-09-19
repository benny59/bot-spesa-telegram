package com.botspesa.app

import android.content.Intent
import android.net.Uri
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
import java.text.NumberFormat
import java.util.Locale

class PreferitiSheet : BottomSheetDialogFragment() {

    private var onItemAdded: (() -> Unit)? = null
    private val addedIds = mutableSetOf<String>()  // ID dei preferiti aggiunti
    private val preferiteItemIds = mutableMapOf<String, Int>()  // Mappa preferite ID → item ID nella lista

    private val gruppoId get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val topicId get() = arguments?.getInt(ARG_TOPIC_ID) ?: 0
    private val userId get() = arguments?.getInt(ARG_USER_ID) ?: 0

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_preferiti, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        caricaPreferiti(view)
        view.findViewById<View>(R.id.btnBackupPreferiti).setOnClickListener { backupPreferiti() }
        view.findViewById<View>(R.id.btnRipristinaPreferiti).setOnClickListener { scaricaBackupPerRipristino() }
    }

    private fun caricaPreferiti(view: View) {
        val favorites = FavoritesStore(requireContext()).all()
        val recycler = view.findViewById<RecyclerView>(R.id.rvPreferiti)
        val empty = view.findViewById<TextView>(R.id.tvPreferitiVuoto)
        empty.visibility = if (favorites.isEmpty()) View.VISIBLE else View.GONE
        recycler.visibility = if (favorites.isEmpty()) View.GONE else View.VISIBLE
        recycler.layoutManager = LinearLayoutManager(requireContext())
        recycler.adapter = PreferitiAdapter(
            favorites,
            addedIds,
            { favorite -> toggleFavorite(favorite, recycler) },
            ::confermaEliminazionePreferito,
            ::apriInformazioniProdotto,
            ::apriFotoPreferito,
            ::apriLinkPreferito,
            ::modificaCategoria
        )
    }

    private fun modificaCategoria(favorite: FavoriteItem) {
        CategoryPicker.show(
            fragment = this,
            gruppoId = gruppoId,
            topicId = topicId,
            userId = userId,
            currentCategoryId = favorite.categoryId,
            currentCategoryName = favorite.categoryName,
            currentCategoryEphemeral = favorite.categoryEphemeral
        ) { category ->
            if (FavoritesStore(requireContext()).updateCategory(
                    favorite.id,
                    category.id,
                    category.name,
                    category.ephemeral
                )
            ) {
                view?.let(::caricaPreferiti)
            } else {
                Toast.makeText(requireContext(), getString(R.string.modifica_non_riuscita), Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun apriInformazioniProdotto(favorite: FavoriteItem) {
        val gtin = favorite.gtin.orEmpty()
        if (gtin.isBlank()) return
        lifecycleScope.launch {
            val preview = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getProductPreview(gtin) }.getOrNull()
            }
            if (preview == null) {
                Toast.makeText(requireContext(), R.string.prodotto_non_trovato, Toast.LENGTH_LONG).show()
                return@launch
            }
            ProductInfoDialog.show(requireContext(), preview, productPreviewText(preview)) {
                aggiornaInformazioniProdotto(gtin)
            }
        }
    }

    private fun aggiornaInformazioniProdotto(gtin: String) {
        lifecycleScope.launch {
            val preview = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getProductPreview(gtin, forceRefresh = true) }.getOrNull()
            }
            if (preview == null) {
                Toast.makeText(requireContext(), R.string.prodotto_non_trovato, Toast.LENGTH_LONG).show()
                return@launch
            }
            ProductInfoDialog.show(requireContext(), preview, productPreviewText(preview)) {
                aggiornaInformazioniProdotto(gtin)
            }
        }
    }

    private fun productPreviewText(preview: ApiClient.ProductPreview): String {
        val format = NumberFormat.getNumberInstance(Locale.ITALY).apply { maximumFractionDigits = 1 }
        val nutrienti = buildList {
            preview.energyKcal100g?.let { add("${format.format(it)} kcal") }
            preview.sugars100g?.let { add("zuccheri ${format.format(it)} g") }
            preview.saturatedFat100g?.let { add("saturi ${format.format(it)} g") }
            preview.salt100g?.let { add("sale ${format.format(it)} g") }
        }
        return buildString {
            append("Open Food Facts")
            if (preview.nutriscoreGrade.isNotBlank()) append(" · Nutri-Score ${preview.nutriscoreGrade.uppercase()}")
            if (nutrienti.isNotEmpty()) append("\nPer 100 g: ${nutrienti.joinToString(" · ")}")
            preview.novaGroup?.let { append("\nGruppo NOVA $it") }
            if (preview.allergens.isNotEmpty()) append("\nAllergeni dichiarati: ${preview.allergens.joinToString(", ")}")
            if (preview.ingredientsText.isNotBlank()) append("\nIngredienti: ${preview.ingredientsText}")
        }
    }

    private fun apriFotoPreferito(favorite: FavoriteItem) {
        val fileId = favorite.telegramPhotoId ?: return
        val fileUniqueId = favorite.telegramPhotoFileName ?: return
        startActivity(Intent(requireContext(), FotoActivity::class.java).apply {
            putExtra(FotoActivity.EXTRA_NOME, favorite.description)
            putExtra(FotoActivity.EXTRA_FOTO_URL, ApiClient.getFavoriteFotoUrl(fileId, fileUniqueId))
        })
    }

    private fun apriLinkPreferito(favorite: FavoriteItem) {
        val raw = favorite.yukaLink.trim()
        if (raw.isBlank()) return
        runCatching { startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(raw))) }
            .onFailure { Toast.makeText(requireContext(), R.string.link_non_disponibile, Toast.LENGTH_SHORT).show() }
    }

    private fun confermaEliminazionePreferito(favorite: FavoriteItem) {
        android.app.AlertDialog.Builder(requireContext())
            .setTitle("Elimina preferito")
            .setMessage("Eliminare definitivamente \"${favorite.description}\" dai preferiti?")
            .setNegativeButton("Annulla", null)
            .setPositiveButton("Elimina") { _, _ ->
                FavoritesStore(requireContext()).remove(favorite.id)
                view?.let(::caricaPreferiti)
            }
            .show()
    }

    private fun backupPreferiti() {
        lifecycleScope.launch {
            val backup = FavoritesStore(requireContext()).backup(userId)
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.backupPreferiti(userId, backup) }
            }
            result.onSuccess { lastBackupAt ->
                Toast.makeText(requireContext(), "Backup completato: $lastBackupAt", Toast.LENGTH_LONG).show()
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Errore backup", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun scaricaBackupPerRipristino() {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { ApiClient.getBackupPreferiti(userId) }
            }
            result.onSuccess { backup ->
                if (backup.schemaVersion != 1 || backup.kind != "favorites-backup" || backup.userId != userId) {
                    Toast.makeText(requireContext(), "Backup preferiti non valido", Toast.LENGTH_LONG).show()
                    return@onSuccess
                }
                confermaRipristino(backup)
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Backup non disponibile", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun confermaRipristino(backup: FavoriteBackup) {
        android.app.AlertDialog.Builder(requireContext())
            .setTitle("Ripristina preferiti")
            .setMessage("Il backup del ${backup.lastBackupAt} contiene ${backup.favorites.size} preferiti. I preferiti locali saranno sostituiti.")
            .setNegativeButton("Annulla", null)
            .setPositiveButton("Ripristina") { _, _ ->
                FavoritesStore(requireContext()).restore(backup)
                Toast.makeText(requireContext(), "Preferiti ripristinati", Toast.LENGTH_SHORT).show()
                dismiss()
            }
            .show()
    }

    private fun toggleFavorite(favorite: FavoriteItem, recycler: RecyclerView) {
        if (favorite.id in addedIds) {
            removeFavorite(favorite, recycler)
        } else {
            addFavorite(favorite, recycler)
        }
    }

    private fun addFavorite(favorite: FavoriteItem, recycler: RecyclerView) {
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    ApiClient.addItem(
                        gruppoId = gruppoId,
                        topicId = topicId,
                        nome = favorite.description,
                        userId = userId,
                        linkUrl = favorite.yukaLink.ifBlank { null },
                        gtin = favorite.gtin.orEmpty().ifBlank { null },
                        splitItems = false,
                        categoriaId = favorite.categoryId.takeIf { it > 0 },
                        telegramPhotoId = favorite.telegramPhotoId,
                        telegramPhotoFileName = favorite.telegramPhotoFileName
                    ).also { if (it.isEmpty()) throw IllegalStateException("Articolo non creato") }
                        .first()
                }
            }
            result.onSuccess { itemId ->
                addedIds.add(favorite.id)
                preferiteItemIds[favorite.id] = itemId
                recycler.adapter?.notifyDataSetChanged()
                onItemAdded?.invoke()
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Errore aggiunta", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun removeFavorite(favorite: FavoriteItem, recycler: RecyclerView) {
        val itemId = preferiteItemIds[favorite.id] ?: return
        lifecycleScope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    ApiClient.removeItem(gruppoId, itemId, userId)
                }
            }
            result.onSuccess {
                addedIds.remove(favorite.id)
                preferiteItemIds.remove(favorite.id)
                recycler.adapter?.notifyDataSetChanged()
                Toast.makeText(requireContext(), "Rimosso dalla lista", Toast.LENGTH_SHORT).show()
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Errore rimozione", Toast.LENGTH_SHORT).show()
            }
        }
    }

    fun setOnItemAddedListener(listener: () -> Unit) {
        onItemAdded = listener
    }

    companion object {
        private const val ARG_GRUPPO_ID = "gruppo_id"
        private const val ARG_TOPIC_ID = "topic_id"
        private const val ARG_USER_ID = "user_id"

        fun newInstance(gruppoId: Int, topicId: Int, userId: Int) = PreferitiSheet().apply {
            arguments = Bundle().apply {
                putInt(ARG_GRUPPO_ID, gruppoId)
                putInt(ARG_TOPIC_ID, topicId)
                putInt(ARG_USER_ID, userId)
            }
        }
    }
}

private class PreferitiAdapter(
    private val favorites: List<FavoriteItem>,
    private val addedIds: Set<String>,
    private val onAdd: (FavoriteItem) -> Unit,
    private val onDelete: (FavoriteItem) -> Unit,
    private val onProduct: (FavoriteItem) -> Unit,
    private val onPhoto: (FavoriteItem) -> Unit,
    private val onLink: (FavoriteItem) -> Unit,
    private val onCategory: (FavoriteItem) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private sealed interface Row {
        data class Category(val name: String, val ephemeral: Boolean) : Row
        data class Favorite(val value: FavoriteItem) : Row
    }

    private val rows = favorites
        .groupBy { it.categoryName to it.categoryEphemeral }
        .entries
        .sortedWith(
            compareBy<Map.Entry<Pair<String, Boolean>, List<FavoriteItem>>>(
                { it.key.first.isBlank() },
                { it.key.second },
                { it.key.first.lowercase(Locale.ITALY) }
            )
        )
        .flatMap { (category, categoryFavorites) ->
            listOf<Row>(Row.Category(category.first, category.second)) + categoryFavorites.map(Row::Favorite)
        }

    class FavoriteViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val status: TextView = view.findViewById(R.id.tvPreferitoStatus)
        val description: TextView = view.findViewById(R.id.tvPreferitoDescrizione)
        val category: TextView = view.findViewById(R.id.tvPreferitoCategoria)
        val link: View = view.findViewById(R.id.ivPreferitoLink)
        val nutrition: View = view.findViewById(R.id.ivPreferitoNutrition)
        val photo: View = view.findViewById(R.id.ivPreferitoFoto)
        val elimina: View = view.findViewById(R.id.tvPreferitoElimina)
    }

    class CategoryViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.tvChecklistCategory)
    }

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is Row.Category -> VIEW_CATEGORY
        is Row.Favorite -> VIEW_FAVORITE
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == VIEW_CATEGORY) {
            CategoryViewHolder(inflater.inflate(R.layout.item_checklist_category, parent, false))
        } else {
            FavoriteViewHolder(inflater.inflate(R.layout.item_preferito, parent, false))
        }
    }

    override fun getItemCount(): Int = rows.size

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is Row.Category -> bindCategory(holder as CategoryViewHolder, row)
            is Row.Favorite -> bindFavorite(holder as FavoriteViewHolder, row.value)
        }
    }

    private fun bindCategory(holder: CategoryViewHolder, row: Row.Category) {
        val displayedName = if (row.ephemeral) row.name.lowercase(Locale.ITALY) else row.name
        val label = if (row.name.isBlank()) {
            holder.itemView.context.getString(R.string.nessuna_categoria)
        } else {
            LocalizationManager.localizedCategoryName(holder.itemView.context, displayedName)
        }
        holder.title.text = "${if (row.ephemeral) "◌" else "▣"} $label"
    }

    private fun bindFavorite(holder: FavoriteViewHolder, favorite: FavoriteItem) {
        val added = favorite.id in addedIds
        holder.status.text = if (added) "✓" else "+"
        holder.status.setBackgroundResource(if (added) R.drawable.circle_initials_green else R.drawable.circle_initials)
        holder.description.text = favorite.description
        holder.category.visibility = View.GONE
        holder.link.visibility = if (favorite.yukaLink.isBlank()) View.GONE else View.VISIBLE
        holder.nutrition.visibility = if (favorite.gtin.isNullOrBlank()) View.GONE else View.VISIBLE
        holder.photo.visibility = if (favorite.telegramPhotoId.isNullOrBlank() || favorite.telegramPhotoFileName.isNullOrBlank()) View.GONE else View.VISIBLE
        holder.link.setOnClickListener { onLink(favorite) }
        holder.nutrition.setOnClickListener { onProduct(favorite) }
        holder.photo.setOnClickListener { onPhoto(favorite) }
        holder.itemView.setOnClickListener(null)
        holder.status.setOnClickListener { onAdd(favorite) }
        holder.elimina.setOnClickListener { onDelete(favorite) }
        val categoryListener = View.OnLongClickListener {
            onCategory(favorite)
            true
        }
        holder.itemView.setOnLongClickListener(categoryListener)
        holder.description.setOnLongClickListener(categoryListener)
    }

    private companion object {
        const val VIEW_CATEGORY = 0
        const val VIEW_FAVORITE = 1
    }
}