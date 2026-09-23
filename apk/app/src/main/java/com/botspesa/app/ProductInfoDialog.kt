package com.botspesa.app

import android.app.AlertDialog
import android.content.Context
import android.view.View
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import coil.load

object ProductInfoDialog {
    fun show(
        context: Context,
        preview: ApiClient.ProductPreview,
        details: String,
        onAdd: (() -> Unit)? = null,
        onRefresh: () -> Unit
    ) {
        val density = context.resources.displayMetrics.density
        val padding = (24 * density).toInt()
        val content = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(padding, 0, padding, padding)
        }

        if (preview.imageUrl.isNotBlank()) {
            content.addView(ImageView(context).apply {
                contentDescription = context.getString(R.string.immagine_ufficiale_prodotto, preview.name)
                adjustViewBounds = true
                scaleType = ImageView.ScaleType.FIT_CENTER
                load(preview.imageUrl) {
                    crossfade(true)
                    listener(onError = { _, _ -> visibility = View.GONE })
                }
            }, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                (220 * density).toInt()
            ).apply {
                bottomMargin = (12 * density).toInt()
            })
        }

        content.addView(TextView(context).apply {
            text = buildString {
                if (preview.brand.isNotBlank()) append("Marchio/Azienda: ${preview.brand}")
                if (preview.manufacturingPlaces.isNotBlank()) {
                    if (isNotEmpty()) append('\n')
                    append("Luogo di produzione: ${preview.manufacturingPlaces}")
                }
                if (details.isNotBlank()) {
                    if (isNotEmpty()) append("\n\n")
                    append(details)
                }
            }
            textSize = 14f
        })

        val scroll = ScrollView(context).apply { addView(content) }
        AlertDialog.Builder(context)
            .setTitle(preview.displayName.ifBlank { context.getString(R.string.informazioni_prodotto) })
            .setView(scroll)
            .setNeutralButton(R.string.aggiorna) { _, _ -> onRefresh() }
            .apply { if (onAdd != null) setNegativeButton(R.string.aggiungi) { _, _ -> onAdd() } }
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }
}