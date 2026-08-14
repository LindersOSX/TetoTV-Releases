package dev.animetv.anime_tv.player

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3ResultBridgeContractTest {
    @Test
    fun `caption choices are returned through MainActivity to Flutter`() {
        val source = File("src/main/kotlin/dev/animetv/anime_tv/MainActivity.kt")
            .readText()
        val nativePlayerResult = source
            .substringAfter("if (requestCode == NATIVE_PLAYER_REQUEST_CODE)", "")
            .substringBefore("super.onActivityResult", "")

        assertTrue(
            nativePlayerResult.contains(
                "Media3PlayerActivity.RESULT_SUBTITLE_BACKGROUND_COLOR to",
            ),
        )
        assertTrue(
            nativePlayerResult.contains(
                "Media3PlayerActivity.RESULT_HIGH_CONTRAST_SUBTITLES to",
            ),
        )
        assertTrue(
            nativePlayerResult.contains(
                "Media3PlayerActivity.RESULT_AUDIO_PREFERENCE_SET to",
            ),
        )
    }

    @Test
    fun `Theme Studio colors are forwarded into native playback`() {
        val source = File("src/main/kotlin/dev/animetv/anime_tv/MainActivity.kt")
            .readText()
        val launch = source
            .substringAfter("private fun startNativePlayer", "")
            .substringBefore("pendingNativePlayerResult = result", "")

        listOf(
            "themeBackgroundColor",
            "themeSurfaceColor",
            "themeAccentColor",
            "themeAccentBrightColor",
            "themeFocusColor",
            "themePrimaryTextColor",
            "themeMutedTextColor",
        ).forEach { key -> assertTrue("Missing $key", launch.contains("\"$key\"")) }
    }
}
