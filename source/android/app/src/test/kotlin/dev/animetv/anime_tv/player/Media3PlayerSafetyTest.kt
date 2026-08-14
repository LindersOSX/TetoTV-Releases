package dev.animetv.anime_tv.player

import java.util.concurrent.Executor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Media3PlayerSafetyTest {
    @Test
    fun `HLS media source factory remains available at runtime`() {
        val factory = Class.forName(
            "androidx.media3.exoplayer.hls.HlsMediaSource\$Factory",
        )

        assertEquals(
            "androidx.media3.exoplayer.hls.HlsMediaSource\$Factory",
            factory.name,
        )
    }

    @Test
    fun `network cleanup never runs inline with Activity destruction`() {
        val queued = mutableListOf<Runnable>()
        val cleanup = Media3NetworkCleanup(Executor(queued::add))
        var callsCanceled = false
        var connectionsEvicted = false

        cleanup.schedule(
            cancelCalls = { callsCanceled = true },
            evictConnections = { connectionsEvicted = true },
        )

        assertEquals(1, queued.size)
        assertFalse(callsCanceled)
        assertFalse(connectionsEvicted)

        queued.single().run()

        assertTrue(callsCanceled)
        assertTrue(connectionsEvicted)
    }

    @Test
    fun `connection eviction still runs when call cancellation fails`() {
        val cleanup = Media3NetworkCleanup(Executor(Runnable::run))
        var connectionsEvicted = false

        cleanup.schedule(
            cancelCalls = { error("synthetic cancellation failure") },
            evictConnections = { connectionsEvicted = true },
        )

        assertTrue(connectionsEvicted)
    }

    @Test
    fun `skip target avoids the exact end of the file`() {
        assertEquals(1_439_000L, safeNativeSkipTargetMs(1_440_000L, 1_440_000L))
        assertEquals(1_290_000L, safeNativeSkipTargetMs(1_290_000L, 1_440_000L))
    }

    @Test
    fun `skip target remains usable before duration is known`() {
        assertEquals(240_000L, safeNativeSkipTargetMs(240_000L, 0L))
        assertEquals(0L, safeNativeSkipTargetMs(-1L, 1_440_000L))
    }

    @Test
    fun `terminal outro is recognized even with the eof guard`() {
        assertTrue(nativeSkipReachesPlaybackEnd(1_440_000L, 1_440_000L))
        assertTrue(nativeSkipReachesPlaybackEnd(1_439_500L, 1_440_000L))
        assertFalse(nativeSkipReachesPlaybackEnd(1_290_000L, 1_440_000L))
    }

    @Test
    fun `consuming an intro leaves a later outro eligible`() {
        val intro = NativeSkipSegment(60_000L, 150_000L, "opening")
        val outro = NativeSkipSegment(1_290_000L, 1_440_000L, "ending")
        val consumed = setOf(nativeSkipSegmentKey(intro))

        assertEquals(
            outro,
            activeNativeSkipSegment(
                positionMs = 1_300_000L,
                segments = listOf(intro, outro),
                consumedSegmentKeys = consumed,
            ),
        )
        assertFalse(nativeSkipSegmentKey(outro) in consumed)
    }

    @Test
    fun `dual and multi audio release labels request extended discovery`() {
        assertTrue(nativeReleaseAdvertisesMultipleAudio("[Group] Show - Dual Audio"))
        assertTrue(nativeReleaseAdvertisesMultipleAudio("Show.Multi-Audio.1080p"))
        assertFalse(nativeReleaseAdvertisesMultipleAudio("Show Japanese Audio 1080p"))
        assertFalse(nativeReleaseAdvertisesMultipleAudio(null))
    }

    @Test
    fun `undefined native track language uses its descriptive label`() {
        assertEquals("English Dub", nativeSelectedTrackLanguage("und", "English Dub"))
        assertEquals("Japanese", nativeSelectedTrackLanguage("zxx", "Japanese"))
        assertEquals("eng", nativeSelectedTrackLanguage("eng", "Japanese"))
        assertEquals(null, nativeSelectedTrackLanguage("mul", ""))
    }

    @Test
    fun `commentary never qualifies as preferred native dialogue`() {
        assertTrue(nativePreferredAudioCandidateIsUsable(140, "eng English Dub"))
        assertFalse(
            nativePreferredAudioCandidateIsUsable(
                140,
                "eng English Director Commentary",
            ),
        )
        assertFalse(nativePreferredAudioCandidateIsUsable(20, "jpn Japanese Stereo"))
    }

    @Test
    fun `provisional audio fallback remains replaceable by a later preferred track`() {
        val provisional = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = false,
            viewerSelectionActive = false,
            candidateMatchesPreference = false,
            candidateMatchesLastOverride = false,
        )
        assertTrue(provisional.applyOverride)
        assertFalse(provisional.markPreferredApplied)

        val repeatedSnapshot = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = provisional.markPreferredApplied,
            viewerSelectionActive = false,
            candidateMatchesPreference = false,
            candidateMatchesLastOverride = true,
        )
        assertFalse(repeatedSnapshot.applyOverride)
        assertFalse(repeatedSnapshot.markPreferredApplied)

        val preferredArrives = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = repeatedSnapshot.markPreferredApplied,
            viewerSelectionActive = false,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = false,
        )
        assertTrue(preferredArrives.applyOverride)
        assertTrue(preferredArrives.markPreferredApplied)
    }

    @Test
    fun `viewer audio selection stops automatic snapshot overrides`() {
        val action = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = false,
            viewerSelectionActive = true,
            candidateMatchesPreference = true,
            candidateMatchesLastOverride = false,
        )

        assertFalse(action.applyOverride)
        assertFalse(action.markPreferredApplied)
    }
}
