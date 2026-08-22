package com.botspesa.app

data class SpesaItem(
    val id: Int,
    val nome: String,
    val linkUrl: String = "",
    val comprato: String,
    val userInitials: String,
    val buyerInitials: String,
    val hasFoto: Boolean = false,
    val gruppoId: Int = 0,
    val topicId: Int = 0,
    val nomeTopic: String = "",
    val nomeGruppo: String = "",
    val nomeContesto: String = "",
    val deleted: Boolean = false,
    val disponibile: Boolean = true
) {
    val isBought: Boolean get() = comprato.isNotEmpty()
    val isDeleted: Boolean get() = deleted
    val isUnavailable: Boolean get() = !disponibile
}
