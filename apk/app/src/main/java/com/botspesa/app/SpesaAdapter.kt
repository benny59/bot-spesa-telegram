package com.botspesa.app

import android.graphics.Paint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
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
    private val contextColor: (SpesaItem) -> Int,
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
        val tvContextSeparator: TextView = view.findViewById(R.id.tvContextSeparator)
        val itemCard: CardView = view.findViewById(R.id.itemCard)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_spesa, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        val mostraContesto = item.nomeContesto.isNotEmpty() &&
            (position == 0 || items[position - 1].gruppoId != item.gruppoId ||
                items[position - 1].topicId != item.topicId)
        holder.tvContextSeparator.visibility = if (mostraContesto) View.VISIBLE else View.GONE
        holder.tvContextSeparator.text = "▸ ${item.nomeContesto}"
        if (mostraContesto) {
            val color = contextColor(item)
            holder.tvContextSeparator.setBackgroundColor(color)
            holder.tvContextSeparator.setTextColor(
                if (ColorUtils.calculateLuminance(color) < 0.45) android.graphics.Color.WHITE
                else android.graphics.Color.BLACK
            )
        }
        holder.tvContextSeparator.setOnClickListener { onContext(item) }
        holder.tvNome.text = item.nome
        if (item.nomeGruppo.isNotEmpty()) {
            holder.tvGruppoNome.visibility = View.VISIBLE
            holder.tvGruppoNome.text = item.nomeGruppo
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

        holder.itemCard.setOnClickListener { onToggle(item) }
        holder.itemCard.setOnLongClickListener { v -> onLongPress(item, v); true }
    }

    override fun getItemCount(): Int = items.size
}
