package com.botspesa.app

import android.graphics.Paint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.cardview.widget.CardView
import androidx.core.graphics.ColorUtils
import androidx.recyclerview.widget.RecyclerView

class SpesaAdapter(
    private val items: MutableList<SpesaItem>,
    private val onToggle: (SpesaItem) -> Unit,
    private val onFoto: (SpesaItem) -> Unit,
    private val onLink: (SpesaItem) -> Unit,
    private val onContext: (SpesaItem) -> Unit,
    private val isFavorite: (SpesaItem) -> Boolean,
    private val onFavorite: (SpesaItem) -> Unit,
    private val contextColor: (SpesaItem) -> Int,
    private val notificationEnabled: (Int) -> Boolean?,
    private val singleContextList: () -> Boolean,
    private val onLongPress: (SpesaItem, android.view.View) -> Unit = { _, _ -> }
) : RecyclerView.Adapter<SpesaAdapter.ViewHolder>() {

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvInitials: TextView      = view.findViewById(R.id.tvInitials)
        val tvInitialsBuyer: TextView = view.findViewById(R.id.tvInitialsBuyer)
        val tvNome: TextView          = view.findViewById(R.id.tvNome)
        val tvGruppoNome: TextView    = view.findViewById(R.id.tvGruppoNome)
        val tvComprato: TextView      = view.findViewById(R.id.tvComprato)
        val ivLink: ImageView         = view.findViewById(R.id.ivLink)
        val ivFoto: ImageView         = view.findViewById(R.id.ivFoto)
        val ivPreferito: ImageView    = view.findViewById(R.id.ivPreferito)
        val contextSeparator: LinearLayout = view.findViewById(R.id.tvContextSeparator)
        val tvContextSeparator: TextView = view.findViewById(R.id.tvContextSeparatorText)
        val ivContextNotification: ImageView = view.findViewById(R.id.ivContextNotification)
        val itemCard: CardView = view.findViewById(R.id.itemCard)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_spesa, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        val listaSingola = singleContextList()
        val categoriaVisualizzata = if (item.categoriaEffimera) item.categoriaNome.lowercase() else item.categoriaNome
        val categoriaTradotta = LocalizationManager.localizedCategoryName(holder.itemView.context, categoriaVisualizzata)
        val separatoreLista = sectionLabel(holder, item)
        val mostraContesto = if (listaSingola) {
            position == 0 || sectionLabel(holder, items[position - 1]) != separatoreLista
        } else {
            item.nomeContesto.isNotEmpty() &&
                (position == 0 || items[position - 1].gruppoId != item.gruppoId ||
                    items[position - 1].topicId != item.topicId)
        }
        holder.contextSeparator.visibility = if (mostraContesto) View.VISIBLE else View.GONE
        holder.tvContextSeparator.text = if (listaSingola) separatoreLista else "▸ ${item.nomeContesto}"
        if (mostraContesto) {
            val color = contextColor(item)
            val textColor = if (ColorUtils.calculateLuminance(color) < 0.45) {
                android.graphics.Color.WHITE
            } else {
                android.graphics.Color.BLACK
            }
            holder.contextSeparator.setBackgroundColor(color)
            holder.tvContextSeparator.setTextColor(textColor)

            val notificheAttive = if (listaSingola) null else notificationEnabled(item.gruppoId)
            val iconRes = when (notificheAttive) {
                true -> R.drawable.ic_volume_up
                false -> R.drawable.ic_volume_off
                null -> 0
            }
            holder.ivContextNotification.visibility = if (iconRes == 0) View.GONE else View.VISIBLE
            if (iconRes != 0) {
                holder.ivContextNotification.setImageResource(iconRes)
                holder.ivContextNotification.setColorFilter(textColor)
            }
            holder.contextSeparator.contentDescription = when (notificheAttive) {
                true -> "${item.nomeContesto}. ${holder.itemView.context.getString(R.string.notifiche_operative_attive)}"
                false -> "${item.nomeContesto}. ${holder.itemView.context.getString(R.string.notifiche_operative_disattivate)}"
                null -> if (listaSingola) separatoreLista else item.nomeContesto
            }
        } else {
            holder.ivContextNotification.visibility = View.GONE
        }
        holder.contextSeparator.isClickable = !listaSingola
        holder.contextSeparator.isFocusable = !listaSingola
        holder.contextSeparator.setOnClickListener(if (listaSingola) null else View.OnClickListener { onContext(item) })
        holder.tvNome.text = item.nome

        val labels = mutableListOf<String>()
        val simboloCategoria = if (item.categoriaEffimera) "◌" else "▣"
        if (!listaSingola && item.categoriaNome.isNotEmpty()) labels.add("$simboloCategoria $categoriaTradotta")
        if (labels.isNotEmpty()) {
            holder.tvGruppoNome.visibility = View.VISIBLE
            holder.tvGruppoNome.text = labels.joinToString(" • ")
        } else {
            holder.tvGruppoNome.visibility = View.GONE
        }

        when {
            item.deleted -> {
                holder.tvNome.paintFlags = holder.tvNome.paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
                holder.tvNome.alpha = 0.6f
                holder.tvComprato.text = "↺"
                holder.tvInitials.visibility = View.VISIBLE
                holder.tvInitials.text = item.userInitials.ifEmpty { "?" }
                holder.tvInitials.alpha = 0.6f
                holder.tvInitials.setBackgroundResource(R.drawable.circle_initials)
                holder.tvInitialsBuyer.visibility = View.GONE
            }
            item.isUnavailable -> {
                holder.tvNome.paintFlags = holder.tvNome.paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
                holder.tvNome.alpha = 0.75f
                holder.tvComprato.text = "✕"
                holder.tvInitials.visibility = View.VISIBLE
                holder.tvInitials.text = item.userInitials.ifEmpty { "?" }
                holder.tvInitials.alpha = 0.75f
                holder.tvInitials.setBackgroundResource(R.drawable.circle_initials)
                holder.tvInitialsBuyer.visibility = View.GONE
            }
            item.isBought -> {
                holder.tvNome.paintFlags = holder.tvNome.paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
                holder.tvNome.alpha = 0.45f
                holder.tvComprato.text = "\u2713"
                val sameUser = item.userInitials == item.buyerInitials
                if (sameUser) {
                    holder.tvInitials.visibility = View.GONE
                } else {
                    holder.tvInitials.visibility = View.VISIBLE
                    holder.tvInitials.text  = item.userInitials.ifEmpty { "?" }
                    holder.tvInitials.alpha = 0.45f
                    holder.tvInitials.setBackgroundResource(R.drawable.circle_initials)
                }
                holder.tvInitialsBuyer.visibility = View.VISIBLE
                holder.tvInitialsBuyer.text  = item.buyerInitials.ifEmpty { item.comprato }
                holder.tvInitialsBuyer.alpha = 1.0f
            }
            else -> {
                holder.tvNome.paintFlags = holder.tvNome.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG.inv()
                holder.tvNome.alpha = 1.0f
                holder.tvComprato.text = ""
                holder.tvInitials.visibility = View.VISIBLE
                holder.tvInitials.text  = item.userInitials.ifEmpty { "?" }
                holder.tvInitials.alpha = 1.0f
                holder.tvInitials.setBackgroundResource(R.drawable.circle_initials)
                holder.tvInitialsBuyer.visibility = View.GONE
            }
        }

        holder.ivLink.visibility = if (item.linkUrl.isNotBlank()) View.VISIBLE else View.GONE
        holder.ivLink.setOnClickListener { onLink(item) }

        holder.ivFoto.visibility = if (item.hasFoto) View.VISIBLE else View.GONE
        holder.ivFoto.setOnClickListener { onFoto(item) }

        holder.ivPreferito.setImageResource(
            if (isFavorite(item)) R.drawable.ic_star else R.drawable.ic_star_border
        )
        holder.ivPreferito.setOnClickListener { onFavorite(item) }

        holder.itemCard.setOnClickListener { onToggle(item) }
        holder.itemCard.setOnLongClickListener { v -> onLongPress(item, v); true }
    }

    override fun getItemCount(): Int = items.size

    private fun sectionLabel(holder: ViewHolder, item: SpesaItem): String {
        return when {
            item.deleted -> holder.itemView.context.getString(R.string.separatore_cancellati)
            item.isBought -> holder.itemView.context.getString(R.string.separatore_nel_carrello)
            item.isUnavailable -> holder.itemView.context.getString(R.string.separatore_non_disponibili)
            item.categoriaNome.isNotEmpty() -> {
                val categoriaVisualizzata = if (item.categoriaEffimera) item.categoriaNome.lowercase() else item.categoriaNome
                LocalizationManager.localizedCategoryName(holder.itemView.context, categoriaVisualizzata)
            }
            else -> holder.itemView.context.getString(R.string.nessuna_categoria)
        }
    }
}
