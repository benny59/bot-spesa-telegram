package com.botspesa.app

import android.graphics.Paint
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.recyclerview.widget.RecyclerView

class ChecklistAdapter(
    private val items: MutableList<ChecklistItem>,
    private val onToggle: (ChecklistItem) -> Unit
) : RecyclerView.Adapter<ChecklistAdapter.ViewHolder>() {

    inner class ViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        val tvStatus: TextView    = view.findViewById(R.id.tvCheckStatus)
        val tvNome: TextView      = view.findViewById(R.id.tvCheckNome)
        val tvConteggio: TextView = view.findViewById(R.id.tvCheckConteggio)
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): ViewHolder {
        val view = LayoutInflater.from(parent.context)
            .inflate(R.layout.item_checklist, parent, false)
        return ViewHolder(view)
    }

    override fun onBindViewHolder(holder: ViewHolder, position: Int) {
        val item = items[position]
        holder.tvConteggio.text = if (item.conteggio > 0) "acquistato ${item.conteggio}×" else ""

        if (item.inLista) {
            holder.tvStatus.text = "✓"
            holder.tvStatus.setBackgroundResource(R.drawable.circle_initials_green)
            holder.tvNome.paintFlags = holder.tvNome.paintFlags or Paint.STRIKE_THRU_TEXT_FLAG
            holder.tvNome.alpha = 0.5f
            holder.tvNome.text = item.nome
        } else {
            holder.tvStatus.text = "+"
            holder.tvStatus.setBackgroundResource(R.drawable.circle_initials)
            holder.tvNome.paintFlags = holder.tvNome.paintFlags and Paint.STRIKE_THRU_TEXT_FLAG.inv()
            holder.tvNome.alpha = 1.0f
            holder.tvNome.text = item.nome
        }

        holder.itemView.setOnClickListener { onToggle(item) }
    }

    override fun getItemCount(): Int = items.size

    fun aggiorna(nuovi: List<ChecklistItem>) {
        items.clear()
        items.addAll(nuovi)
        notifyDataSetChanged()
    }
}
