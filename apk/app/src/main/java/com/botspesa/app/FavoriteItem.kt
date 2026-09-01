package com.botspesa.app

data class FavoriteItem(
    val id: String,
    val description: String,
    val categoryId: Int,
    val categoryName: String,
    val categoryEphemeral: Boolean,
    val yukaLink: String,
    // TODO: populate when the item API exposes Telegram photo metadata.
    val telegramPhotoId: String? = null,
    val telegramPhotoFileName: String? = null,
    val groupId: Int? = null,
    val topicId: Int? = null
)