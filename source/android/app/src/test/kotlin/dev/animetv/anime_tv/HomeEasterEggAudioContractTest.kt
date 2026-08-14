package dev.animetv.anime_tv

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeEasterEggAudioContractTest {
    @Test
    fun `audio lifetime is capped at ten seconds`() {
        assertEquals(10_000L, HomeEasterEggAudio.MAXIMUM_DURATION_MS)
    }

    @Test
    fun `main activity releases decoration audio when destroyed`() {
        val relativeSource = "src/main/kotlin/dev/animetv/anime_tv/MainActivity.kt"
        val workingDirectory = System.getProperty("user.dir") ?: "."
        val sourceFile = generateSequence(File(workingDirectory)) { it.parentFile }
            .take(6)
            .flatMap { directory ->
                sequenceOf(
                    File(directory, relativeSource),
                    File(directory, "app/$relativeSource"),
                    File(directory, "android/app/$relativeSource"),
                )
            }
            .firstOrNull(File::isFile)
        assertTrue("MainActivity source must be available", sourceFile != null)
        val onDestroy = sourceFile!!.readText()
            .substringAfter("override fun onDestroy()", "")
            .substringBefore("companion object")
        assertTrue(onDestroy.contains("homeEasterEggAudio.stop()"))
    }
}
