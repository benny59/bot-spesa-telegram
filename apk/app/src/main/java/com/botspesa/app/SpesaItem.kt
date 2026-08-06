package com.botspesa.app

data class SpesaItem(
    val id: Int,
    val nome: String,
    val comprato: String,
    val userInitials: String,
    val hasFoto: Boolean = false
) {
    val isBought: Boolean get() = comprato.isNotEmpty()
}
