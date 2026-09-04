package com.botspesa.app

data class FavoriteBackup(
    val schemaVersion: Int = 1,
    val kind: String = "favorites-backup",
    val userId: Int,
    val lastBackupAt: String,
    val favorites: List<FavoriteItem>
)