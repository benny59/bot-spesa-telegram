package com.botspesa.app

data class CartaFedeltaItem(
    val id: Int,
    val nome: String,
    val codice: String,
    val formato: String,
    val condivisaConGruppo: Boolean = false
)
