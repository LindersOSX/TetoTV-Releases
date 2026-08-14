package dev.animetv.anime_tv

import android.app.ApplicationExitInfo
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AnonymousCrashStoreTest {
    @Test
    fun `only crash and ANR exit reasons are reportable`() {
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_CRASH))
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_CRASH_NATIVE))
        assertTrue(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_ANR))
        assertFalse(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_EXIT_SELF))
        assertFalse(AnonymousCrashStore.isReportableReason(ApplicationExitInfo.REASON_USER_REQUESTED))
    }

    @Test
    fun `native descriptions are redacted and bounded`() {
        val output = AnonymousCrashStore.sanitize(
            "failed https://private.example/watch Bearer secret token=private " +
                "magnet:?xt=urn:btih:123 ${"a".repeat(64)}\nnext",
            140,
        )

        assertTrue(output.contains("[URL]"))
        assertTrue(output.contains("Bearer [REDACTED]"))
        assertTrue(output.contains("[MAGNET]"))
        assertFalse(output.contains("private.example"))
        assertFalse(output.contains("token=private"))
        assertFalse(output.contains("secret"))
        assertFalse(output.contains("a".repeat(40)))
        assertTrue(output.length <= 140)
    }

    @Test
    fun `native descriptions redact local paths but preserve stack class names`() {
        val output = AnonymousCrashStore.sanitize(
            "content://com.android.providers.media.documents/document/video%3Aprivate-show.mkv\n" +
                "file:///storage/emulated/0/Private%20Episode.mkv\n" +
                "teto+private:document-id-episode-42\n" +
                "/storage/emulated/0/Private Show Episode 7.mkv\n" +
                "C:\\Users\\Viewer\\Videos\\Private Episode 8.mkv\n" +
                "at dev.animetv.anime_tv.player.Media3PlayerActivity.onDestroy" +
                "(Media3PlayerActivity.kt:169)",
            1_000,
        )

        assertTrue(output.contains("[URI]"))
        assertTrue(output.contains("[PATH]"))
        assertFalse(output.contains("private-show"))
        assertFalse(output.contains("document-id-episode-42"))
        assertFalse(output.contains("Private Show Episode 7.mkv"))
        assertFalse(output.contains("Private Episode 8.mkv"))
        assertTrue(
            output.contains(
                "dev.animetv.anime_tv.player.Media3PlayerActivity.onDestroy" +
                    "(Media3PlayerActivity.kt:169)",
            ),
        )
    }
}
