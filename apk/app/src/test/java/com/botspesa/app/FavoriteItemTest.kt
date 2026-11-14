package com.botspesa.app

import com.google.gson.Gson
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FavoriteItemTest {
    @Test
    fun `legacy favorite without gtin remains addable`() {
        val favorite = Gson().fromJson(
            """{"id":"legacy","description":"Latte","categoryId":0,"categoryName":"","categoryEphemeral":false,"yukaLink":""}""",
            FavoriteItem::class.java
        )

        val gtinForApi = favorite.gtin.orEmpty().ifBlank { null }

        assertNull(gtinForApi)
    }

    private fun fav(gtin: String? = null, link: String = "", cat: Int = 0, nome: String = "Yogurt greco") =
        FavoriteItem("f", nome, cat, "", false, link, gtin)

    private fun item(gtin: String = "", link: String = "", cat: Int = 0, nome: String = "Yogurt greco") =
        SpesaItem(id = 1, nome = nome, gtin = gtin, linkUrl = link, comprato = "", userInitials = "", buyerInitials = "", categoriaId = cat)

    @Test
    fun `favorite enriched with gtin and link still matches a plain item`() {
        assertTrue(fav(gtin = "8076809513722", link = "https://app.yuka.io/p/1").matches(item()))
    }

    @Test
    fun `different gtin or link or name or category does not match`() {
        assertFalse(fav(gtin = "8076809513722").matches(item(gtin = "8000300155877")))
        assertFalse(fav(link = "https://app.yuka.io/p/1").matches(item(link = "https://app.yuka.io/p/2")))
        assertFalse(fav().matches(item(nome = "Latte")))
        assertFalse(fav(cat = 3).matches(item(cat = 4)))
    }
}
