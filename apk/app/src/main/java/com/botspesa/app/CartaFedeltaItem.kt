package com.botspesa.app

import android.graphics.Color

data class CartaFedeltaItem(
    val id: Int,
    val nome: String,
    val codice: String,
    val formato: String,
    val condivisaConGruppo: Boolean = false,
    val isMia: Boolean = true
) {
    fun statusMarker(): Pair<String, Int> = when {
        isMia && condivisaConGruppo -> "🟢" to Color.parseColor("#2E7D32")
        isMia -> "🟡" to Color.parseColor("#8D6E00")
        else -> "🔵" to Color.parseColor("#1565C0")
    }
}
