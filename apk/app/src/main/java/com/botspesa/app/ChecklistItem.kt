package com.botspesa.app

data class ChecklistItem(
    val id: Int,
    val nome: String,
    val nomeDisplay: String,
    val conteggio: Int,
    val categoriaId: Int,
    val categoriaNome: String,
    val categoriaEffimera: Boolean,
    val gtin: String,
    val yukaUrl: String,
    val inLista: Boolean
)
