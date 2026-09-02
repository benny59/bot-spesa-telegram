package com.botspesa.app

data class FavoriteItem(
    val id: String,
    val description: String,
    val categoryId: Int,
    val categoryName: String,
    val categoryEphemeral: Boolean,
    val yukaLink: String,
    val telegramPhotoId: String? = null,
    val telegramPhotoFileName: String? = null,
    val telegramPhotoDate: String? = null,
    val groupId: Int? = null,
    val topicId: Int? = null
)