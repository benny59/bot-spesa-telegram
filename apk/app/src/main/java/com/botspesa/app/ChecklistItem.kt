package com.botspesa.app

data class ChecklistItem(
    val nome: String,
    val nomeDisplay: String,
    val conteggio: Int,
    val categoriaNome: String,
    val categoriaEffimera: Boolean,
    val inLista: Boolean
)
