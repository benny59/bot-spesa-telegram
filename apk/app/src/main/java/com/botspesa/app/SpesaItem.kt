package com.botspesa.app

data class SpesaItem(
    val id: Int,
    val nome: String,
    val comprato: String,
    val userInitials: String,
    val hasFoto: Boolean = false,
    val gruppoId: Int = 0,
    val topicId: Int = 0,
    val nomeGruppo: String = "",
    val nomeContesto: String = ""
) {
    val isBought: Boolean get() = comprato.isNotEmpty()
}
