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

// Un preferito coincide con un articolo solo con stesso nome, categoria, link Yuka e GTIN: un articolo scritto a mano
// resta generico e non è "il" preferito specifico solo perché il nome è uguale.
fun FavoriteItem.matches(item: SpesaItem): Boolean =
    description == item.nome &&
        categoryId == item.categoriaId &&
        yukaLink == item.linkUrl &&
        gtin.orEmpty() == item.gtin
