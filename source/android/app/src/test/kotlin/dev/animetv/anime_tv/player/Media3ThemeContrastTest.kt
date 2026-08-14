package dev.animetv.anime_tv.player

import org.junit.Assert.assertEquals
import org.junit.Test

class Media3ThemeContrastTest {
    @Test
    fun `dark accents use a white action foreground`() {
        assertEquals(
            0xFFFFFFFF.toInt(),
            nativeThemeContrastForeground(0xFF101010.toInt()),
        )
    }

    @Test
    fun `light accents use a black action foreground`() {
        assertEquals(
            0xFF000000.toInt(),
            nativeThemeContrastForeground(0xFFF4F4F4.toInt()),
        )
    }

    @Test
    fun `white accent does not disappear against white primary text`() {
        assertEquals(
            0xFF000000.toInt(),
            nativeThemeAccentForeground(
                hasCustomTheme = true,
                accent = 0xFFFFFFFF.toInt(),
                legacyForeground = 0xFFFFFFFF.toInt(),
            ),
        )
    }

    @Test
    fun `default native HUD retains its legacy foreground exactly`() {
        val legacyForeground = 0xFFF8F5F6.toInt()
        assertEquals(
            legacyForeground,
            nativeThemeAccentForeground(
                hasCustomTheme = false,
                accent = 0xFFFFFFFF.toInt(),
                legacyForeground = legacyForeground,
            ),
        )
    }
}
