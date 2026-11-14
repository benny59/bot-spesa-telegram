package com.botspesa.app

import android.content.Context
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File
import java.time.Instant
import java.util.UUID

class FavoritesStore(context: Context) {
    private val file = File(context.filesDir, FILE_NAME)
    private val gson = Gson()

    fun all(): List<FavoriteItem> = runCatching {
        if (!file.exists()) return emptyList()
        gson.fromJson<List<FavoriteItem>>(file.readText(), FAVORITES_TYPE).orEmpty()
    }.getOrDefault(emptyList())

    fun contains(item: SpesaItem): Boolean = all().any { it.matches(item) }

    fun backup(userId: Int): FavoriteBackup = FavoriteBackup(
        userId = userId,
        lastBackupAt = Instant.now().toString(),
        favorites = all()
    )

    fun restore(backup: FavoriteBackup) {
        save(backup.favorites)
    }

    fun toggle(item: SpesaItem): Boolean {
        val favorites = all().toMutableList()
        // più preferiti possono coincidere (stesso nome, prodotti diversi): se ne toglie uno, il più vicino all'articolo
        val existingIndex = favorites.withIndex()
            .filter { it.value.matches(item) }
            .maxByOrNull { closeness(it.value, item) }?.index ?: -1
        if (existingIndex >= 0) {
            favorites.removeAt(existingIndex)
            save(favorites)
            return false
        }

        favorites.add(item.toFavorite())
        save(favorites)
        return true
    }

    fun remove(favoriteId: String) {
        val favorites = all().toMutableList()
        if (favorites.removeAll { it.id == favoriteId }) {
            save(favorites)
        }
    }

    fun updateCategory(favoriteId: String, categoryId: Int?, categoryName: String, categoryEphemeral: Boolean): Boolean {
        val favorites = all().toMutableList()
        val index = favorites.indexOfFirst { it.id == favoriteId }
        if (index < 0) return false

        favorites[index] = favorites[index].copy(
            categoryId = categoryId ?: 0,
            categoryName = categoryName,
            categoryEphemeral = categoryEphemeral
        )
        save(favorites)
        return true
    }

    private fun closeness(f: FavoriteItem, item: SpesaItem): Int =
        (if (!f.gtin.isNullOrBlank() && f.gtin == item.gtin) 2 else 0) +
            (if (f.yukaLink.isNotBlank() && f.yukaLink == item.linkUrl) 1 else 0)

    private fun save(favorites: List<FavoriteItem>) {
        val temporaryFile = File(file.parentFile, "$FILE_NAME.tmp")
        temporaryFile.writeText(gson.toJson(favorites))
        if (!temporaryFile.renameTo(file)) {
            temporaryFile.copyTo(file, overwrite = true)
            temporaryFile.delete()
        }
    }

    private fun SpesaItem.toFavorite() = FavoriteItem(
        id = UUID.randomUUID().toString(),
        description = nome,
        categoryId = categoriaId,
        categoryName = categoriaNome,
        categoryEphemeral = categoriaEffimera,
        yukaLink = linkUrl,
        gtin = gtin,
        telegramPhotoId = telegramPhotoId,
        telegramPhotoFileName = telegramPhotoFileName,
        telegramPhotoDate = telegramPhotoDate
    )

    private companion object {
        const val FILE_NAME = "favorites.json"
        val FAVORITES_TYPE = object : TypeToken<List<FavoriteItem>>() {}.type
    }
}