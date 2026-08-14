package dev.animetv.anime_tv

import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper

/** Owns the short, local-only sound used by the Home screen decoration. */
internal class HomeEasterEggAudio(context: Context) {
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private val stopRunnable = Runnable(::releaseActivePlayer)

    fun play(requestedMaximumDurationMs: Long) {
        releaseActivePlayer()
        val next = MediaPlayer.create(appContext, R.raw.teto_easter_egg) ?: return
        player = next
        next.setOnCompletionListener { completed ->
            if (player === completed) {
                player = null
                handler.removeCallbacks(stopRunnable)
            }
            runCatching { completed.release() }
        }
        next.setOnErrorListener { failed, _, _ ->
            if (player === failed) player = null
            handler.removeCallbacks(stopRunnable)
            runCatching { failed.release() }
            true
        }
        val durationMs = requestedMaximumDurationMs.coerceIn(
            MINIMUM_DURATION_MS,
            MAXIMUM_DURATION_MS,
        )
        handler.postDelayed(stopRunnable, durationMs)
        try {
            next.start()
        } catch (_: RuntimeException) {
            releaseActivePlayer()
        }
    }

    fun stop() {
        releaseActivePlayer()
    }

    private fun releaseActivePlayer() {
        handler.removeCallbacks(stopRunnable)
        val active = player ?: return
        player = null
        active.setOnCompletionListener(null)
        active.setOnErrorListener(null)
        runCatching { active.stop() }
        runCatching { active.release() }
    }

    companion object {
        const val MAXIMUM_DURATION_MS = 10_000L
        private const val MINIMUM_DURATION_MS = 100L
    }
}
