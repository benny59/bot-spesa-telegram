package com.botspesa.app

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.util.UUID

class FavoritesStore(context: Context) {
    private val file = File(context.filesDir, FILE_NAME)
    private val gson = Gson()

    fun all(): List<FavoriteItem> = runCatching {
        if (!file.exists()) return emptyList()
        gson.fromJson<List<FavoriteItem>>(file.readText(), FAVORITES_TYPE).orEmpty()
    }.getOrDefault(emptyList())

    fun contains(item: SpesaItem): Boolean = all().any { it.matches(item) }

    fun toggle(item: SpesaItem): Boolean {
        val favorites = all().toMutableList()
        val existingIndex = favorites.indexOfFirst { it.matches(item) }
        if (existingIndex >= 0) {
            favorites.removeAt(existingIndex)
            save(favorites)
            return false
        }

        favorites.add(item.toFavorite())
        save(favorites)
        return true
    }

    private fun save(favorites: List<FavoriteItem>) {
        val temporaryFile = File(file.parentFile, "$FILE_NAME.tmp")
        temporaryFile.writeText(gson.toJson(favorites))
        if (!temporaryFile.renameTo(file)) {
            temporaryFile.copyTo(file, overwrite = true)
            temporaryFile.delete()
        }
    }

    private fun FavoriteItem.matches(item: SpesaItem): Boolean =
        description == item.nome &&
            categoryId == item.categoriaId &&
            yukaLink == item.linkUrl

    private fun SpesaItem.toFavorite() = FavoriteItem(
        id = UUID.randomUUID().toString(),
        description = nome,
        categoryId = categoriaId,
        categoryName = categoriaNome,
        categoryEphemeral = categoriaEffimera,
        yukaLink = linkUrl,
        telegramPhotoId = telegramPhotoId,
        telegramPhotoFileName = telegramPhotoFileName,
        telegramPhotoDate = telegramPhotoDate
    )

    private companion object {
        const val FILE_NAME = "favorites.json"
        val FAVORITES_TYPE = object : TypeToken<List<FavoriteItem>>() {}.type
    }
}