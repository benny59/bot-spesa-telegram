package com.botspesa.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalizationManagerTest {
    @Test
    fun `supported languages include italian and german`() {
        val languages = LocalizationManager.supportedLanguages()

        assertTrue(languages.any { it.code == "it" })
        assertTrue(languages.any { it.code == "de" })
    }

    @Test
    fun `returns default language when missing`() {
        assertEquals("it", LocalizationManager.normalizeLanguageCode(""))
        assertEquals("it", LocalizationManager.normalizeLanguageCode("fr"))
        assertEquals("de", LocalizationManager.normalizeLanguageCode("de"))
    }
}
