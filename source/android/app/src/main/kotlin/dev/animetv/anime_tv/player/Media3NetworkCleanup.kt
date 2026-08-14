package dev.animetv.anime_tv.player

import java.util.concurrent.Executor
import java.util.concurrent.Executors

/**
 * Keeps OkHttp socket cancellation and eviction away from Android's main
 * thread. Conscrypt may write TLS close-notify bytes while closing a socket,
 * which throws NetworkOnMainThreadException on Android 11/Fire OS when done
 * directly from Activity.onDestroy().
 */
internal class Media3NetworkCleanup(
    private val executor: Executor,
) {
    fun schedule(
        cancelCalls: () -> Unit,
        evictConnections: () -> Unit,
    ) {
        runCatching {
            executor.execute {
                runCatching(cancelCalls)
                runCatching(evictConnections)
            }
        }
    }

    companion object {
        val shared = Media3NetworkCleanup(
            Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "TetoTV-Media3-network-cleanup").apply {
                    isDaemon = true
                }
            },
        )
    }
}
