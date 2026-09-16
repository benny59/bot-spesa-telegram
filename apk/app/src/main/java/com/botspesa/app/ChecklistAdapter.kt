package com.botspesa.app

import android.graphics.Paint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class ChecklistAdapter(
    private val items: MutableList<ChecklistItem>,
    private val onToggle: (ChecklistItem) -> Unit
) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {

    private sealed interface Row {
        data class Category(val name: String, val ephemeral: Boolean) : Row
        data class Item(val value: ChecklistItem) : Row
    }

    private val rows = mutableListOf<Row>()

    inner class ItemViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val status: ImageView     = view.findViewById(R.id.tvCheckStatus)
        val tvNome: TextView      = view.findViewById(R.id.tvCheckNome)
        val tvConteggio: TextView = view.findViewById(R.id.tvCheckConteggio)
    }

    inner class CategoryViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val title: TextView = view.findViewById(R.id.tvChecklistCategory)
    }

    override fun getItemViewType(position: Int): Int = when (rows[position]) {
        is Row.Category -> VIEW_CATEGORY
        is Row.Item -> VIEW_ITEM
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return if (viewType == VIEW_CATEGORY) {
            CategoryViewHolder(inflater.inflate(R.layout.item_checklist_category, parent, false))
        } else {
            ItemViewHolder(inflater.inflate(R.layout.item_checklist, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val row = rows[position]) {
            is Row.Category -> bindCategory(holder as CategoryViewHolder, row)
            is Row.Item -> bindItem(holder as ItemViewHolder, row.value)
        }
    }

    private fun bindCategory(holder: CategoryViewHolder, row: Row.Category) {
        val visualizzata = if (row.ephemeral) row.name.lowercase() else row.name
        val label = if (row.name.isBlank()) {
            holder.itemView.context.getString(R.string.nessuna_categoria)
        } else {
            LocalizationManager.localizedCategoryName(holder.itemView.context, visualizzata)
        }
        holder.title.text = "${if (row.ephemeral) "◌" else "▣"} $label"
    }

    private fun bindItem(holder: ItemViewHolder, item: ChecklistItem) {
        holder.tvNome.text = item.nomeDisplay
        holder.tvConteggio.text = if (item.conteggio > 0) "acquistato ${item.conteggio}×" else ""
        holder.tvConteggio.visibility = if (item.conteggio > 0) View.VISIBLE else View.GONE

        holder.status.setImageResource(if (item.inLista) R.drawable.ic_check_white else R.drawable.ic_add_white)
        holder.status.setBackgroundResource(if (item.inLista) R.drawable.circle_initials_green else R.drawable.circle_initials)
        holder.status.contentDescription = holder.itemView.context.getString(
            if (item.inLista) R.string.rimuovi else R.string.aggiungi
        )
        holder.tvNome.paintFlags = if (item.inLista) {
            holder.tvNome.paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
        } else {
            holder.tvNome.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG.inv()
        }
        holder.tvNome.alpha = if (item.inLista) 0.5f else 1f

        holder.itemView.setOnClickListener { onToggle(item) }
        holder.status.setOnClickListener { onToggle(item) }
    }

    override fun getItemCount(): Int = rows.size

    fun aggiorna(nuovi: List<ChecklistItem>) {
        items.clear()
        items.addAll(nuovi)
        rows.clear()
        nuovi.groupBy { Pair(it.categoriaNome, it.categoriaEffimera) }.forEach { (category, categoryItems) ->
            rows.add(Row.Category(category.first, category.second))
            rows.addAll(categoryItems.map(Row::Item))
        }
        notifyDataSetChanged()
    }

    private companion object {
        const val VIEW_CATEGORY = 0
        const val VIEW_ITEM = 1
    }
}
