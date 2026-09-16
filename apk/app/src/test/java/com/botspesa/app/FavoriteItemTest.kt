package com.botspesa.app

import com.google.gson.Gson
import org.junit.Assert.assertNull
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
}