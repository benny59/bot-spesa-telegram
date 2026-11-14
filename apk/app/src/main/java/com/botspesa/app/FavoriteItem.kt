package com.botspesa.app

data class FavoriteItem(
    val id: String,
    val description: String,
    val categoryId: Int,
    val categoryName: String,
    val categoryEphemeral: Boolean,
    val yukaLink: String,
    val gtin: String? = null,
    val telegramPhotoId: String? = null,
    val telegramPhotoFileName: String? = null,
    val telegramPhotoDate: String? = null,
    val groupId: Int? = null,
    val topicId: Int? = null
)

// Stesso nome e categoria; link Yuka e GTIN contano solo se presenti da entrambe le parti, così un preferito
// integrato con GTIN/link continua a coincidere con l'articolo in lista che ne è privo.
fun FavoriteItem.matches(item: SpesaItem): Boolean =
    description == item.nome &&
        categoryId == item.categoriaId &&
        fieldsCompatible(yukaLink, item.linkUrl) &&
        fieldsCompatible(gtin.orEmpty(), item.gtin)

private fun fieldsCompatible(a: String, b: String): Boolean = a.isBlank() || b.isBlank() || a == b
