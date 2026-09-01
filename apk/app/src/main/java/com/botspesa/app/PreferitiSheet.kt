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

class PreferitiSheet : BottomSheetDialogFragment() {

    private var onItemAdded: (() -> Unit)? = null
    private val addedIds = mutableSetOf<String>()

    private val gruppoId get() = arguments?.getInt(ARG_GRUPPO_ID) ?: 0
    private val topicId get() = arguments?.getInt(ARG_TOPIC_ID) ?: 0
    private val userId get() = arguments?.getInt(ARG_USER_ID) ?: 0

    override fun onCreateView(inflater: LayoutInflater, container: ViewGroup?, savedInstanceState: Bundle?): View =
        inflater.inflate(R.layout.fragment_preferiti, container, false)

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        val favorites = FavoritesStore(requireContext()).all()
        val recycler = view.findViewById<RecyclerView>(R.id.rvPreferiti)
        val empty = view.findViewById<TextView>(R.id.tvPreferitiVuoto)
        empty.visibility = if (favorites.isEmpty()) View.VISIBLE else View.GONE
        recycler.visibility = if (favorites.isEmpty()) View.GONE else View.VISIBLE
        recycler.layoutManager = LinearLayoutManager(requireContext())
        recycler.adapter = PreferitiAdapter(favorites, addedIds) { favorite -> addFavorite(favorite, recycler) }
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
                        splitItems = favorite.yukaLink.isBlank(),
                        categoriaId = favorite.categoryId.takeIf { it > 0 }
                    ).also { if (it.isEmpty()) throw IllegalStateException("Articolo non creato") }
                    // TODO: reuse telegramPhotoId when the backend accepts Telegram photo references.
                }
            }
            result.onSuccess {
                addedIds.add(favorite.id)
                recycler.adapter?.notifyDataSetChanged()
                onItemAdded?.invoke()
            }.onFailure {
                Toast.makeText(requireContext(), it.message ?: "Errore aggiunta", Toast.LENGTH_SHORT).show()
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
    private val onAdd: (FavoriteItem) -> Unit
) : RecyclerView.Adapter<PreferitiAdapter.ViewHolder>() {

    class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val status: TextView = view.findViewById(R.id.tvPreferitoStatus)
        val description: TextView = view.findViewById(R.id.tvPreferitoDescrizione)
        val category: TextView = view.findViewById(R.id.tvPreferitoCategoria)
        val link: View = view.findViewById(R.id.ivPreferitoLink)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder = ViewHolder(
        LayoutInflater.from(parent.context).inflate(R.layout.item_preferito, parent, false)
    )

    override fun getItemCount(): Int = favorites.size

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val favorite = favorites[position]
        val added = favorite.id in addedIds
        holder.status.text = if (added) "✓" else "+"
        holder.status.setBackgroundResource(if (added) R.drawable.circle_initials_green else R.drawable.circle_initials)
        holder.description.text = favorite.description
        val category = if (favorite.categoryName.isNotBlank()) {
            "${if (favorite.categoryEphemeral) "◌" else "▣"} ${LocalizationManager.localizedCategoryName(holder.itemView.context, favorite.categoryName)}"
        } else ""
        holder.category.visibility = if (category.isEmpty()) View.GONE else View.VISIBLE
        holder.category.text = category
        holder.link.visibility = if (favorite.yukaLink.isBlank()) View.GONE else View.VISIBLE
        holder.itemView.setOnClickListener { onAdd(favorite) }
    }
}