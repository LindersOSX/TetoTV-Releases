package dev.animetv.anime_tv.player

import android.annotation.SuppressLint
import android.app.ActivityManager
import android.app.Dialog
import android.content.res.ColorStateList
import android.content.Intent
import android.graphics.Color
import android.graphics.Rect
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.LayerDrawable
import android.graphics.drawable.StateListDrawable
import android.net.Uri
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.PathInterpolator
import android.widget.ImageButton
import android.widget.Button
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.Toast
import android.widget.TextView
import androidx.annotation.OptIn
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import android.app.AlertDialog
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.session.MediaSession
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerView
import androidx.media3.ui.TrackSelectionDialogBuilder
import dev.animetv.anime_tv.R
import dev.animetv.anime_tv.DiscordRichPresenceBridge
import dev.animetv.anime_tv.security.NetworkRequestPolicy
import dev.animetv.anime_tv.security.PublicNetworkDns
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import org.json.JSONObject
import java.io.IOException

internal fun safeNativeSkipTargetMs(
    requestedMs: Long,
    durationMs: Long,
    endGuardMs: Long = 1_000L,
): Long {
    if (requestedMs <= 0L) return 0L
    if (durationMs <= 0L) return requestedMs
    val lastSafePosition = (durationMs - endGuardMs).coerceAtLeast(0L)
    return requestedMs.coerceAtMost(lastSafePosition)
}

internal fun nativeSkipReachesPlaybackEnd(
    requestedEndMs: Long,
    durationMs: Long,
    endGuardMs: Long = 1_000L,
): Boolean = durationMs > 0L && requestedEndMs >= durationMs - endGuardMs

internal fun nativeReleaseAdvertisesMultipleAudio(releaseName: String?): Boolean {
    val normalized = releaseName
        .orEmpty()
        .lowercase()
        .replace(Regex("[^a-z0-9]+"), " ")
        .trim()
    return Regex("\\b(?:dual|multi) audio\\b").containsMatchIn(normalized)
}

internal fun nativeSelectedTrackLanguage(language: String?, label: String?): String? {
    val normalized = language.orEmpty().trim().lowercase()
    if (normalized.isNotEmpty() && normalized !in setOf("und", "zxx", "mul")) {
        return language?.trim()
    }
    return label?.trim()?.takeIf(String::isNotEmpty)
}

/**
 * Chooses the same black-or-white foreground as Flutter's
 * `contrastForeground`, using WCAG relative luminance.
 *
 * This is kept Android-framework-free so JVM contract tests can verify light
 * and dark Theme Studio accents without relying on mocked [Color] methods.
 */
internal fun nativeThemeContrastForeground(background: Int): Int {
    fun linear(channel: Int): Double {
        val value = channel / 255.0
        return if (value <= 0.03928) value / 12.92
        else Math.pow((value + 0.055) / 1.055, 2.4)
    }
    val red = background ushr 16 and 0xFF
    val green = background ushr 8 and 0xFF
    val blue = background and 0xFF
    val luminance =
        0.2126 * linear(red) +
            0.7152 * linear(green) +
            0.0722 * linear(blue)
    return if (luminance > 0.179) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
}

/** Preserve the exact legacy foreground unless Theme Studio is customized. */
internal fun nativeThemeAccentForeground(
    hasCustomTheme: Boolean,
    accent: Int,
    legacyForeground: Int,
): Int = if (hasCustomTheme) nativeThemeContrastForeground(accent) else legacyForeground

internal fun nativePreferredAudioCandidateIsUsable(score: Int, description: String): Boolean {
    val normalized = description.lowercase()
    val isCommentary = "commentary" in normalized ||
        "descriptive" in normalized ||
        "description" in normalized
    return score >= 50 && !isCommentary
}

internal data class NativePreferredAudioOverrideAction(
    val applyOverride: Boolean,
    val markPreferredApplied: Boolean,
)

/**
 * Keeps a provisional audio fallback replaceable while Media3 is still
 * publishing tracks for the current item.
 *
 * Some Matroska streams first expose only their default Japanese track and add
 * the English/Dub track in a later [Player.Listener.onTracksChanged] snapshot.
 * A fallback override is useful for avoiding commentary, but it must not make
 * preferred-language discovery terminal. The last-override check also avoids
 * an onTracksChanged loop when applying that provisional override.
 */
internal fun nativePreferredAudioOverrideAction(
    preferredAlreadyApplied: Boolean,
    viewerSelectionActive: Boolean,
    candidateMatchesPreference: Boolean,
    candidateMatchesLastOverride: Boolean,
): NativePreferredAudioOverrideAction {
    if (preferredAlreadyApplied || viewerSelectionActive) {
        return NativePreferredAudioOverrideAction(
            applyOverride = false,
            markPreferredApplied = false,
        )
    }
    return NativePreferredAudioOverrideAction(
        applyOverride = !candidateMatchesLastOverride,
        markPreferredApplied = candidateMatchesPreference,
    )
}

internal data class NativeSkipSegment(
    val startMs: Long,
    val endMs: Long,
    val kind: String,
)

internal fun nativeSkipSegmentKey(segment: NativeSkipSegment): String =
    "${segment.kind}:${segment.startMs}"

internal fun activeNativeSkipSegment(
    positionMs: Long,
    segments: List<NativeSkipSegment>,
    consumedSegmentKeys: Set<String>,
): NativeSkipSegment? = segments.firstOrNull { segment ->
    positionMs >= segment.startMs &&
        positionMs < segment.endMs - 500L &&
        nativeSkipSegmentKey(segment) !in consumedSegmentKeys
}

/**
 * Full-screen native Android playback isolated from Flutter's texture pipeline.
 *
 * [PlayerView] creates a real [SurfaceView] by default. Keeping this in a
 * separate Activity avoids Flutter TextureRegistry, virtual-display, and
 * platform-view composition paths that corrupt frames on some Fire TV devices.
 */
@OptIn(UnstableApi::class)
class Media3PlayerActivity : ComponentActivity(), Player.Listener, AnalyticsListener {
    private lateinit var player: ExoPlayer
    private lateinit var playerView: PlayerView
    private lateinit var mediaSession: MediaSession
    private lateinit var audioTrackButton: ImageButton
    private lateinit var captionTrackButton: ImageButton
    private lateinit var captionSizeButton: ImageButton
    private lateinit var pictureModeButton: ImageButton
    private lateinit var fixVideoButton: ImageButton
    private lateinit var sourcesButton: ImageButton
    private lateinit var optionsButton: ImageButton
    private lateinit var playPauseButton: ImageButton
    private lateinit var rewindControlContainer: View
    private lateinit var playPauseControlContainer: View
    private lateinit var fastForwardControlContainer: View
    private lateinit var audioControlContainer: View
    private lateinit var captionControlContainer: View
    private lateinit var skipSegmentButton: Button
    private lateinit var pausedTitleView: TextView
    private val handler = Handler(Looper.getMainLooper())
    private val metadataClient = OkHttpClient.Builder()
        .dns(PublicNetworkDns())
        .connectTimeout(6, TimeUnit.SECONDS)
        .readTimeout(8, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private var source = ""
    private var playbackProxyOrigin: NetworkRequestPolicy.Origin? = null
    private var displayTitle = "TetoTV"
    private var artworkUrl = ""
    private var checkpointKey = ""
    private var firstFrameRendered = false
    private var everFirstFrameRendered = false
    private var surfaceReady = false
    private var decoderName: String? = null
    private var droppedFrames = 0
    private var terminalError: String? = null
    private var resultSent = false
    private var preserveDiscordPresenceForEngineHandoff = false
    private var suppressDiscordPresence = false
    private var playbackResourcesReleased = false
    private var playerViewReleased = false
    private var playerListenersReleased = false
    private var mediaSessionReleased = false
    private var playerCoreReleased = false
    private var resumeProvided = false
    private var requestedResumeMs = 0L
    private var requestedResumeUpdatedAtMs = 0L
    private var resumeAfterTransientPause = false
    private var isForeground = false
    private var preferredAudioLanguage = "eng"
    private var audioPreferenceChanged = false
    private var preferredSubtitleLanguage = "eng"
    private var subtitlesEnabled = true
    private var subtitleSize = 34f
    private var subtitlePosition = 100
    private var highContrastSubtitles = false
    private var subtitleTextColor = Color.WHITE
    private var subtitleBackgroundColor = Color.TRANSPARENT
    private var hasCustomNativeTheme = false
    private var themeBackgroundColor = Color.BLACK
    private var themeSurfaceColor = LEGACY_THEME_SURFACE
    private var themeAccentColor = LEGACY_THEME_ACCENT
    private var themeAccentBrightColor = LEGACY_THEME_ACCENT_BRIGHT
    private var themeFocusColor = LEGACY_THEME_FOCUS
    private var themePrimaryTextColor = Color.WHITE
    private var themeMutedTextColor = LEGACY_THEME_MUTED_TEXT
    private var seekBackIncrementMs = 10_000L
    private var seekForwardIncrementMs = 10_000L
    private var autoSkipIntros = false
    private var autoSkipOutros = false
    private var hasDirectSources = false
    private var videoResizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
    private var preferredAudioOverrideApplied = false
    private var lastAutomaticAudioOverride: TrackSelectionOverride? = null
    private var preferredSubtitleOverrideApplied = false
    private var backgroundStopped = false
    private var backgroundResumeMs = 0L
    private var dropWindowElapsedMs = 0L
    private var dropWindowFrames = 0
    private var consecutiveChoppyWindows = 0
    private var activeTrackDialog: Dialog? = null
    private var pendingAudioTrackPicker: Runnable? = null
    private var consumedNavigationKeyUp: Int? = null
    private var malMediaId = 0
    private var episodeNumber = 0
    private var skipFetchComplete = false
    private var skipFetchInFlight = false
    private var skipFetchAttempts = 0
    private var skipDurationCandidateMs = 0L
    private var activeSkipSegment: NativeSkipSegment? = null
    private val skipSegments = mutableListOf<NativeSkipSegment>()
    private val autoFocusedSkipSegments = mutableSetOf<String>()
    private val autoSkippedSegments = mutableSetOf<String>()
    private var exitDialog: AlertDialog? = null

    private val checkpointPreferences by lazy {
        getSharedPreferences(CHECKPOINT_PREFERENCES, MODE_PRIVATE)
    }

    private val checkpointRunnable = object : Runnable {
        override fun run() {
            persistCheckpoint()
            publishDiscordPresence()
            if (!isFinishing && !isDestroyed && isForeground) {
                handler.postDelayed(this, CHECKPOINT_INTERVAL_MS)
            }
        }
    }

    private val hideControllerRunnable = Runnable {
        if (
            ::playerView.isInitialized &&
            activeTrackDialog?.isShowing != true &&
            !isFinishing &&
            !isDestroyed
        ) {
            playerView.hideController()
        }
    }

    private val skipSegmentRunnable = object : Runnable {
        override fun run() {
            updateSkipSegmentButton()
            if (!isFinishing && !isDestroyed && isForeground) {
                handler.postDelayed(this, SKIP_SEGMENT_POLL_MS)
            }
        }
    }

    private val skipFetchRetryRunnable = Runnable { fetchSkipSegmentsIfReady() }
    private val skipDurationStabilityRunnable = Runnable { fetchSkipSegmentsIfReady() }

    private val firstFrameWatchdog = Runnable {
        if (
            resultSent || !isForeground || firstFrameRendered || !hasSelectedVideoTrack()
        ) return@Runnable
        val position = safePositionMs()
        terminalError =
            "Media3 reached a playable state but the SurfaceView received no video frame " +
                "(position=${position}ms, decoder=${decoderName ?: "unknown"}, " +
                "surfaceReady=$surfaceReady)."
        finishWithResult(STATUS_ERROR)
    }

    private val startupWatchdog = Runnable {
        if (resultSent || !isForeground || firstFrameRendered) return@Runnable
        terminalError = if (hasSelectedVideoTrack()) {
            "Media3 did not render a video frame within ${STARTUP_TIMEOUT_MS / 1_000}s " +
                "(state=${player.playbackState}, decoder=${decoderName ?: "unknown"})."
        } else {
            "Media3 did not discover a playable video track within " +
                "${STARTUP_TIMEOUT_MS / 1_000}s."
        }
        finishWithResult(STATUS_ERROR)
    }

    private val surfaceCallback = object : SurfaceHolder.Callback {
        override fun surfaceCreated(holder: SurfaceHolder) {
            surfaceReady = true
            if (
                isForeground &&
                ::player.isInitialized &&
                player.playbackState == Player.STATE_READY &&
                !firstFrameRendered
            ) {
                handler.removeCallbacks(firstFrameWatchdog)
                handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
            }
        }

        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            surfaceReady = width > 0 && height > 0
        }

        override fun surfaceDestroyed(holder: SurfaceHolder) {
            surfaceReady = false
            firstFrameRendered = false
            resetDropWindow()
            handler.removeCallbacks(firstFrameWatchdog)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() = showExitConfirmation()
            },
        )
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        enterImmersiveMode()
        readNativePlayerTheme()
        if (intent.getBooleanExtra(EXTRA_SUBTITLE_REJECTED, false)) {
            Toast.makeText(
                this,
                "Playing without unsafe or unsupported external subtitles.",
                Toast.LENGTH_LONG,
            ).show()
        }

        source = normalizeMediaUri(intent.getStringExtra(EXTRA_SOURCE).orEmpty())
        displayTitle = intent.getStringExtra(EXTRA_TITLE).orEmpty().ifBlank { "TetoTV" }
        artworkUrl = intent.getStringExtra(EXTRA_ARTWORK_URL).orEmpty()
        checkpointKey = intent.getStringExtra(EXTRA_CHECKPOINT_KEY).orEmpty()
        resumeProvided = intent.getBooleanExtra(EXTRA_RESUME_PROVIDED, false)
        requestedResumeMs = intent.getLongExtra(EXTRA_RESUME_MS, 0L).coerceAtLeast(0L)
        requestedResumeUpdatedAtMs =
            intent.getLongExtra(EXTRA_RESUME_UPDATED_AT_MS, 0L).coerceAtLeast(0L)
        malMediaId = intent.getIntExtra(EXTRA_MAL_MEDIA_ID, 0).coerceAtLeast(0)
        episodeNumber = intent.getIntExtra(EXTRA_EPISODE_NUMBER, 0).coerceAtLeast(0)
        hasDirectSources = intent.getBooleanExtra(EXTRA_HAS_DIRECT_SOURCES, false)
        val trustedLocalSource = intent.getBooleanExtra(EXTRA_TRUSTED_LOCAL_SOURCE, false)
        val trustedPlaybackProxy =
            intent.getBooleanExtra(EXTRA_TRUSTED_PLAYBACK_PROXY, false)
        suppressDiscordPresence = trustedLocalSource
        if (suppressDiscordPresence) {
            // Local filenames and private media-server titles are not part of
            // the viewer's public anime activity. Never disclose them through
            // Discord Rich Presence, even when Discord is linked globally.
            DiscordRichPresenceBridge.clearPlayback()
        }
        val publicSourceOrigin = NetworkRequestPolicy.httpsOrigin(source)
        val localSourceOrigin = if (trustedLocalSource) {
            NetworkRequestPolicy.trustedLocalMediaOrigin(source)
        } else {
            null
        }
        playbackProxyOrigin = if (trustedPlaybackProxy) {
            NetworkRequestPolicy.trustedPlaybackProxyOrigin(source)
        } else {
            null
        }
        val trustedContentSource = trustedLocalSource &&
            NetworkRequestPolicy.isTrustedContentUri(source)
        val sourceOrigin = playbackProxyOrigin ?: localSourceOrigin ?: publicSourceOrigin
        if (
            source.isBlank() ||
            (sourceOrigin == null && !trustedContentSource && source != SMOKE_VIDEO_URI)
        ) {
            terminalError = "The native player requires a supported media URL."
            finishWithResult(STATUS_ERROR)
            return
        }

        preferredAudioLanguage =
            intent.getStringExtra(EXTRA_AUDIO_LANGUAGE)?.ifBlank { "eng" } ?: "eng"
        val audioLanguages = preferredLanguageTags(preferredAudioLanguage)
        val audioLabels = preferredAudioLabels(
            preferredAudioLanguage,
        )
        preferredSubtitleLanguage =
            intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE)?.ifBlank { "eng" } ?: "eng"
        val subtitleLanguages = preferredLanguageTags(preferredSubtitleLanguage)
        subtitlesEnabled = intent.getBooleanExtra(EXTRA_SUBTITLES_ENABLED, true)
        subtitleSize = intent.getFloatExtra(EXTRA_SUBTITLE_SIZE, 34f).coerceIn(18f, 60f)
        subtitlePosition =
            intent.getIntExtra(EXTRA_SUBTITLE_POSITION, 100).coerceIn(60, 100)
        highContrastSubtitles =
            intent.getBooleanExtra(EXTRA_HIGH_CONTRAST_SUBTITLES, false)
        subtitleTextColor = intent.getIntExtra(EXTRA_SUBTITLE_TEXT_COLOR, Color.WHITE)
        subtitleBackgroundColor =
            intent.getIntExtra(EXTRA_SUBTITLE_BACKGROUND_COLOR, Color.TRANSPARENT)
        seekBackIncrementMs =
            intent.getLongExtra(EXTRA_SEEK_BACK_MS, 10_000L).coerceIn(5_000L, 60_000L)
        seekForwardIncrementMs =
            intent.getLongExtra(EXTRA_SEEK_FORWARD_MS, 10_000L).coerceIn(5_000L, 60_000L)
        autoSkipIntros = intent.getBooleanExtra(EXTRA_AUTO_SKIP_INTROS, false)
        autoSkipOutros = intent.getBooleanExtra(EXTRA_AUTO_SKIP_OUTROS, false)
        videoResizeMode = when (intent.getStringExtra(EXTRA_VIDEO_FIT)) {
            "cover" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        val trackSelector = DefaultTrackSelector(this).apply {
            parameters = buildUponParameters()
                .setPreferredAudioLanguages(*audioLanguages.toTypedArray())
                .setPreferredAudioLabels(*audioLabels.toTypedArray())
                .setPreferredTextLanguages(*subtitleLanguages.toTypedArray())
                // Anime releases frequently leave an otherwise valid English
                // ASS/SRT track's language undefined. Prefer it only when no
                // explicitly preferred-language track is available.
                .setSelectUndeterminedTextLanguage(subtitlesEnabled)
                .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, !subtitlesEnabled)
                .build()
        }
        val renderersFactory = DefaultRenderersFactory(this)
            .setEnableDecoderFallback(true)

        // Size the progressive buffer for the device instead of assuming a
        // particular Fire TV, Shield, Chromecast, or generic Android TV box.
        val activityManager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
        val lowMemoryDevice = activityManager.isLowRamDevice
        val memoryClassMb = activityManager.memoryClass
        val minimumBufferMs = if (lowMemoryDevice) 8_000 else 12_000
        val maximumBufferMs = when {
            lowMemoryDevice -> 25_000
            memoryClassMb <= 256 -> 35_000
            else -> 45_000
        }
        // Keep the allocator below roughly one quarter of the app heap. The
        // Flutter engine remains alive behind this Activity, so allowing a 4K
        // remux to ignore the byte limit can otherwise force low-memory TV
        // boxes into GC thrashing or an OOM.
        val targetBufferBytes =
            (memoryClassMb / 4).coerceIn(16, 96) * 1024 * 1024
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                minimumBufferMs,
                maximumBufferMs,
                1_500,
                3_000,
            )
            .setTargetBufferBytes(targetBufferBytes)
            .setPrioritizeTimeOverSizeThresholds(false)
            .setBackBuffer(5_000, false)
            .build()

        val suppliedHeaders = NetworkRequestPolicy.sanitizeRequestHeaders(intentHeaders())
        val httpClientBuilder = OkHttpClient.Builder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .followRedirects(true)
            .followSslRedirects(true)
            .retryOnConnectionFailure(true)
        // Public add-on/debrid URLs must never resolve to the LAN. A Jellyfin
        // URL entered by the viewer is explicitly marked trusted and uses
        // system DNS only for HTTPS; cleartext HTTP is numeric-private-only.
        if (localSourceOrigin == null && playbackProxyOrigin == null) {
            httpClientBuilder.dns(PublicNetworkDns())
        }
        if (sourceOrigin != null && suppliedHeaders.isNotEmpty()) {
            // The same Media3 data-source factory also loads external subtitle
            // files and cross-origin playlist segments. Never forward account
            // credentials or add-on-specific secret headers outside the exact
            // origin for which they were supplied.
            httpClientBuilder.addNetworkInterceptor { chain ->
                val request = chain.request()
                val requestOrigin = NetworkRequestPolicy.origin(
                    request.url.scheme,
                    request.url.host,
                    request.url.port,
                )
                val builder = request.newBuilder()
                suppliedHeaders.keys
                    .filterNot { header ->
                        NetworkRequestPolicy.shouldForwardHeader(
                            header,
                            sourceOrigin,
                            requestOrigin,
                        )
                    }
                    .forEach(builder::removeHeader)
                chain.proceed(builder.build())
            }
        }
        val httpClient = httpClientBuilder.build()
        val requestHeaders = linkedMapOf(
            "Accept" to "*/*",
            "User-Agent" to "TetoTV/1.7 AndroidTV Media3",
        ).apply { putAll(suppliedHeaders) }
        val httpFactory = OkHttpDataSource.Factory(httpClient)
            .setUserAgent(requestHeaders.getValue("User-Agent"))
            .setDefaultRequestProperties(requestHeaders)
        val dataSourceFactory = DefaultDataSource.Factory(this, httpFactory)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(this, renderersFactory)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(mediaSourceFactory)
            .setSeekBackIncrementMs(seekBackIncrementMs)
            .setSeekForwardIncrementMs(seekForwardIncrementMs)
            .build()
            .also {
                it.addListener(this)
                it.addAnalyticsListener(this)
                it.setAudioAttributes(
                    AudioAttributes.Builder()
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .setUsage(C.USAGE_MEDIA)
                        .build(),
                    true,
                )
                it.setHandleAudioBecomingNoisy(true)
                // Ask Android to match 23.976/24/25/50/60 fps only when the
                // display can do so without a disruptive mode switch. This
                // reduces judder on capable TVs while remaining safe on boxes
                // that expose only a fixed 60 Hz output mode.
                it.videoChangeFrameRateStrategy =
                    C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_ONLY_IF_SEAMLESS
            }

        setContentView(R.layout.activity_media3_player)
        playerView = findViewById<PlayerView>(R.id.tetotv_player_view).apply {
            setBackgroundColor(Color.BLACK)
            setShutterBackgroundColor(Color.BLACK)
            useController = true
            // Media3 otherwise keeps controls visible forever while paused.
            // TetoTV uses one deterministic inactivity policy in every state.
            controllerAutoShow = false
            controllerHideOnTouch = true
            controllerShowTimeoutMs = CONTROLLER_HIDE_TIMEOUT_MS.toInt()
            setShowPreviousButton(false)
            setShowNextButton(false)
            setShowRewindButton(true)
            setShowFastForwardButton(true)
            // TetoTV owns the explicit, TV-focusable caption picker below.
            setShowSubtitleButton(false)
            setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
            setKeepContentOnPlayerReset(false)
            resizeMode = videoResizeMode
            subtitleView?.apply {
                val customCaptionColors =
                    subtitleTextColor != Color.WHITE || subtitleBackgroundColor != Color.TRANSPARENT
                setApplyEmbeddedStyles(!highContrastSubtitles && !customCaptionColors)
                setApplyEmbeddedFontSizes(
                    !highContrastSubtitles && subtitleSize == DEFAULT_SUBTITLE_SIZE,
                )
                setFixedTextSize(
                    TypedValue.COMPLEX_UNIT_SP,
                    subtitleSize,
                )
                setBottomPaddingFraction((108 - subtitlePosition) / 100f)
                if (highContrastSubtitles || customCaptionColors) {
                    setStyle(
                        CaptionStyleCompat(
                            subtitleTextColor,
                            if (highContrastSubtitles) 0xDD000000.toInt()
                            else subtitleBackgroundColor,
                            Color.TRANSPARENT,
                            CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                            Color.BLACK,
                            null,
                        ),
                    )
                }
            }
            player = this@Media3PlayerActivity.player
        }
        configurePlayerChromeBounds()
        audioTrackButton = playerView.findViewById<ImageButton>(R.id.tetotv_audio_tracks).apply {
            setOnClickListener {
                showTrackPicker(C.TRACK_TYPE_AUDIO, this)
            }
        }
        captionTrackButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_caption_tracks).apply {
                setOnClickListener {
                    showTrackPicker(C.TRACK_TYPE_TEXT, this)
                }
            }
        captionSizeButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_caption_size).apply {
                setOnClickListener { showSubtitleSizePicker(this) }
            }
        pictureModeButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_picture_mode).apply {
                setOnClickListener { cyclePictureMode(this) }
            }
        fixVideoButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_fix_video).apply {
                setOnClickListener { showPlayerPicker(this) }
            }
        sourcesButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_player_sources).apply {
                visibility = if (hasDirectSources) View.VISIBLE else View.GONE
                setOnClickListener { finishWithResult(STATUS_NEXT_STREAM) }
            }
        playerView.findViewById<View>(R.id.tetotv_sources_control).visibility =
            if (hasDirectSources) View.VISIBLE else View.GONE
        playerView.findViewById<View>(R.id.tetotv_sources_spacing).visibility =
            if (hasDirectSources) View.VISIBLE else View.GONE
        optionsButton =
            playerView.findViewById<ImageButton>(R.id.tetotv_player_options).apply {
                setOnClickListener { showPlaybackOptions(this) }
            }
        fixVideoButton.nextFocusRightId =
            if (hasDirectSources) R.id.tetotv_player_sources else R.id.tetotv_player_options
        optionsButton.nextFocusLeftId =
            if (hasDirectSources) R.id.tetotv_player_sources else R.id.tetotv_fix_video
        rewindControlContainer = playerView.findViewById(R.id.tetotv_rewind_control)
        playPauseControlContainer = playerView.findViewById(R.id.tetotv_play_pause_control)
        fastForwardControlContainer = playerView.findViewById(R.id.tetotv_fast_forward_control)
        audioControlContainer = playerView.findViewById(R.id.tetotv_audio_control)
        captionControlContainer = playerView.findViewById(R.id.tetotv_caption_control)
        playPauseButton =
            playerView.findViewById<ImageButton>(androidx.media3.ui.R.id.exo_play_pause).apply {
                setImageResource(R.drawable.tetotv_ic_play_arrow_rounded)
            }
        skipSegmentButton =
            findViewById<Button>(R.id.tetotv_skip_segment).apply {
                visibility = View.GONE
                applyTvSafeActionLabelTextSize(
                    tvSafeHudTextSizePx(HUD_SKIP_LABEL_SIZE_DP),
                )
                setOnClickListener {
                    val segment = activeSkipSegment ?: return@setOnClickListener
                    seekPastSkipSegment(segment, announce = false)
                }
                setOnKeyListener { _, keyCode, event ->
                    if (
                        event.action == KeyEvent.ACTION_DOWN &&
                        event.repeatCount == 0 &&
                        keyCode in SKIP_TO_CONTROLLER_KEYS
                    ) {
                        // The floating skip action is useful on TV, but it must
                        // never become a D-pad island. One direction press
                        // reveals the HUD and returns focus to Play/Pause.
                        consumedNavigationKeyUp = keyCode
                        playerView.showController()
                        requestTransportFocus()
                        armControllerAutoHide()
                        true
                    } else {
                        false
                    }
                }
            }
        playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                updateSkipSegmentButtonPosition(visibility == View.VISIBLE)
            },
        )
        updateSkipSegmentButtonPosition(playerView.isControllerFullyVisible)
        pausedTitleView = playerView.findViewById<TextView>(R.id.tetotv_paused_title).apply {
            text = intent.getStringExtra(EXTRA_TITLE).orEmpty()
            visibility = View.GONE
        }
        playerView.findViewById<TextView>(R.id.tetotv_controller_title).text =
            intent.getStringExtra(EXTRA_TITLE).orEmpty()
        playerView.findViewById<TextView>(R.id.tetotv_stream_label).text =
            intent.getStringExtra(EXTRA_STREAM_LABEL).orEmpty().ifBlank { "Debrid stream" }
        applyNativePlayerTheme()
        updateCaptionSizeDescription()
        playerView.findViewById<ImageButton>(androidx.media3.ui.R.id.exo_rew).apply {
            setImageResource(R.drawable.tetotv_ic_replay_rounded)
            contentDescription = getString(
                R.string.tetotv_player_rewind_seconds,
                seekBackIncrementMs / 1_000,
            )
            setOnClickListener { seekRelative(-seekBackIncrementMs, it) }
        }
        playerView.findViewById<ImageButton>(androidx.media3.ui.R.id.exo_ffwd).apply {
            setImageResource(R.drawable.tetotv_ic_forward_rounded)
            contentDescription = getString(
                R.string.tetotv_player_fast_forward_seconds,
                seekForwardIncrementMs / 1_000,
            )
            setOnClickListener { seekRelative(seekForwardIncrementMs, it) }
        }
        bindChromeControlSurface(R.id.tetotv_rewind_control, androidx.media3.ui.R.id.exo_rew)
        bindChromeControlSurface(
            R.id.tetotv_play_pause_control,
            androidx.media3.ui.R.id.exo_play_pause,
        )
        bindChromeControlSurface(
            R.id.tetotv_fast_forward_control,
            androidx.media3.ui.R.id.exo_ffwd,
        )
        bindChromeControlSurface(R.id.tetotv_audio_control, R.id.tetotv_audio_tracks)
        bindChromeControlSurface(R.id.tetotv_caption_control, R.id.tetotv_caption_tracks)
        bindChromeControlSurface(R.id.tetotv_caption_size_control, R.id.tetotv_caption_size)
        bindChromeControlSurface(R.id.tetotv_picture_control, R.id.tetotv_picture_mode)
        bindChromeControlSurface(R.id.tetotv_player_control, R.id.tetotv_fix_video)
        if (hasDirectSources) {
            bindChromeControlSurface(R.id.tetotv_sources_control, R.id.tetotv_player_sources)
        }
        bindChromeControlSurface(R.id.tetotv_options_control, R.id.tetotv_player_options)
        updateTransportControlAvailability(player.availableCommands)
        val videoSurface = playerView.videoSurfaceView
        if (videoSurface !is SurfaceView) {
            terminalError =
                "Media3 did not create the required direct SurfaceView " +
                    "(${videoSurface?.javaClass?.name ?: "none"})."
            finishWithResult(STATUS_ERROR)
            return
        }
        videoSurface.holder.addCallback(surfaceCallback)
        mediaSession = MediaSession.Builder(this, player)
            // Media3 requires IDs to remain unique until the prior Activity's
            // asynchronous destruction has released its session. This matters
            // for auto-next and immediate retry/fallback launches.
            .setId("TetoTVNativePlayer-${SystemClock.elapsedRealtimeNanos()}")
            .build()

        val startFromBeginning = intent.getBooleanExtra(EXTRA_START_FROM_BEGINNING, false)
        val nativeCheckpointMs = if (checkpointKey.isBlank()) {
            0L
        } else {
            checkpointPreferences.getLong(positionKey(), 0L)
        }
        val nativeCheckpointUpdatedAtMs = if (checkpointKey.isBlank()) {
            0L
        } else {
            checkpointPreferences.getLong(updatedKey(), 0L)
        }
        val nativeCheckpointCompleted = checkpointKey.isNotBlank() &&
            checkpointPreferences.getBoolean(completedKey(), false)
        if (startFromBeginning && checkpointKey.isNotBlank()) clearNativeCheckpoint()
        val startPositionMs = when {
            startFromBeginning -> 0L
            nativeCheckpointCompleted -> {
                if (
                    resumeProvided &&
                    (nativeCheckpointUpdatedAtMs == 0L ||
                        requestedResumeUpdatedAtMs >= nativeCheckpointUpdatedAtMs)
                ) requestedResumeMs else 0L
            }
            resumeProvided && requestedResumeUpdatedAtMs >= nativeCheckpointUpdatedAtMs ->
                requestedResumeMs
            nativeCheckpointUpdatedAtMs > 0L -> nativeCheckpointMs
            resumeProvided -> requestedResumeMs
            else -> 0L
        }.coerceAtLeast(0L)
        player.setMediaItem(buildMediaItem(), startPositionMs)
        player.prepare()
        player.playWhenReady = intent.getBooleanExtra(EXTRA_AUTO_PLAY, true)
        playerView.showController()
        requestTransportFocus()
        armControllerAutoHide()
    }

    private fun buildMediaItem(): MediaItem {
        val builder = MediaItem.Builder()
            .setUri(Uri.parse(source))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(displayTitle).build())

        inferContainerMimeType(
            intent.getStringExtra(EXTRA_MIME_TYPE),
            intent.getStringExtra(EXTRA_FILE_NAME),
            source,
        )?.let(builder::setMimeType)

        val subtitleUrl = intent.getStringExtra(EXTRA_SUBTITLE_URL)?.let(::normalizeMediaUri)
        val allowedSubtitleUrl = subtitleUrl?.takeIf {
            it == SMOKE_SUBTITLE_URI ||
                NetworkRequestPolicy.httpsOrigin(it) != null ||
                (playbackProxyOrigin != null &&
                    NetworkRequestPolicy.trustedPlaybackProxyOrigin(it) == playbackProxyOrigin)
        }
        if (!allowedSubtitleUrl.isNullOrBlank()) {
            val subtitleMime = inferSubtitleMimeType(
                intent.getStringExtra(EXTRA_SUBTITLE_MIME_TYPE),
                allowedSubtitleUrl,
            )
            val subtitle = MediaItem.SubtitleConfiguration.Builder(Uri.parse(allowedSubtitleUrl))
                .setMimeType(subtitleMime)
                .setLanguage(intent.getStringExtra(EXTRA_SUBTITLE_LANGUAGE) ?: "en")
                .setLabel(intent.getStringExtra(EXTRA_SUBTITLE_LABEL) ?: "Subtitles")
                .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
                .build()
            builder.setSubtitleConfigurations(listOf(subtitle))
        }
        return builder.build()
    }

    private fun intentHeaders(): Map<String, String> {
        @Suppress("DEPRECATION", "UNCHECKED_CAST")
        val values = intent.getSerializableExtra(EXTRA_HEADERS) as? HashMap<String, String>
        return values.orEmpty()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (resultSent || playbackResourcesReleased) return
        updatePlaybackIntentUi()
        when (playbackState) {
            Player.STATE_READY -> {
                handler.removeCallbacks(firstFrameWatchdog)
                fetchSkipSegmentsIfReady()
                publishDiscordPresence()
                if (isForeground && !firstFrameRendered && hasSelectedVideoTrack()) {
                    handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
                }
            }
            Player.STATE_ENDED -> finishWithResult(STATUS_COMPLETED)
            Player.STATE_BUFFERING, Player.STATE_IDLE -> Unit
        }
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        if (resultSent || playbackResourcesReleased) return
        updatePlaybackIntentUi()
        publishDiscordPresence()
    }

    override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
        if (resultSent || playbackResourcesReleased) return
        updatePlaybackIntentUi()
        publishDiscordPresence()
    }

    private fun isPlaybackIntended(): Boolean =
        player.playWhenReady && player.playbackState != Player.STATE_ENDED

    private fun updatePlaybackIntentUi() {
        if (!::player.isInitialized) return
        val playbackIntended = isPlaybackIntended()
        if (::pausedTitleView.isInitialized) {
            pausedTitleView.visibility = if (playbackIntended) View.GONE else View.VISIBLE
        }
        if (::playPauseButton.isInitialized) {
            playPauseButton.contentDescription = getString(
                if (playbackIntended) R.string.tetotv_player_pause
                else R.string.tetotv_player_play,
            )
            val icon = if (playbackIntended) {
                R.drawable.tetotv_ic_pause_rounded
            } else {
                R.drawable.tetotv_ic_play_arrow_rounded
            }
            // PlayerControlView refreshes its stock image from the same player
            // event. Re-apply the app-owned MPV glyph after that listener has
            // finished so the native engine cannot visually drift.
            playPauseButton.setImageResource(icon)
            playPauseButton.post {
                if (!isFinishing && !isDestroyed && ::player.isInitialized) {
                    val currentIcon = if (isPlaybackIntended()) {
                        R.drawable.tetotv_ic_pause_rounded
                    } else {
                        R.drawable.tetotv_ic_play_arrow_rounded
                    }
                    playPauseButton.setImageResource(currentIcon)
                }
            }
        }
    }

    override fun onAvailableCommandsChanged(availableCommands: Player.Commands) {
        updateTransportControlAvailability(availableCommands)
    }

    private fun readNativePlayerTheme() {
        val contracts = listOf(
            EXTRA_THEME_BACKGROUND_COLOR to FLUTTER_DEFAULT_BACKGROUND,
            EXTRA_THEME_SURFACE_COLOR to FLUTTER_DEFAULT_SURFACE,
            EXTRA_THEME_ACCENT_COLOR to LEGACY_THEME_ACCENT,
            EXTRA_THEME_ACCENT_BRIGHT_COLOR to LEGACY_THEME_ACCENT_BRIGHT,
            EXTRA_THEME_FOCUS_COLOR to LEGACY_THEME_FOCUS,
            EXTRA_THEME_PRIMARY_TEXT_COLOR to FLUTTER_DEFAULT_PRIMARY_TEXT,
            EXTRA_THEME_MUTED_TEXT_COLOR to LEGACY_THEME_MUTED_TEXT,
        )
        hasCustomNativeTheme = contracts.any { (key, defaultColor) ->
            intent.hasExtra(key) && intent.getIntExtra(key, defaultColor) != defaultColor
        }
        themeBackgroundColor = themeColorExtra(
            EXTRA_THEME_BACKGROUND_COLOR,
            FLUTTER_DEFAULT_BACKGROUND,
            Color.BLACK,
        )
        themeSurfaceColor = themeColorExtra(
            EXTRA_THEME_SURFACE_COLOR,
            FLUTTER_DEFAULT_SURFACE,
            LEGACY_THEME_SURFACE,
        )
        themeAccentColor = themeColorExtra(
            EXTRA_THEME_ACCENT_COLOR,
            LEGACY_THEME_ACCENT,
            LEGACY_THEME_ACCENT,
        )
        themeAccentBrightColor = themeColorExtra(
            EXTRA_THEME_ACCENT_BRIGHT_COLOR,
            LEGACY_THEME_ACCENT_BRIGHT,
            LEGACY_THEME_ACCENT_BRIGHT,
        )
        themeFocusColor = themeColorExtra(
            EXTRA_THEME_FOCUS_COLOR,
            LEGACY_THEME_FOCUS,
            LEGACY_THEME_FOCUS,
        )
        themePrimaryTextColor = themeColorExtra(
            EXTRA_THEME_PRIMARY_TEXT_COLOR,
            FLUTTER_DEFAULT_PRIMARY_TEXT,
            Color.WHITE,
        )
        themeMutedTextColor = themeColorExtra(
            EXTRA_THEME_MUTED_TEXT_COLOR,
            LEGACY_THEME_MUTED_TEXT,
            LEGACY_THEME_MUTED_TEXT,
        )
    }

    private fun themeColorExtra(key: String, flutterDefault: Int, legacyDefault: Int): Int {
        if (!intent.hasExtra(key)) return legacyDefault
        val supplied = intent.getIntExtra(key, legacyDefault)
        return if (supplied == flutterDefault) legacyDefault else supplied
    }

    /** Apply Theme Studio colors without changing the original default HUD palette. */
    private fun applyNativePlayerTheme() {
        if (!hasCustomNativeTheme) return
        window.navigationBarColor = themeBackgroundColor
        window.statusBarColor = themeBackgroundColor
        findViewById<View>(android.R.id.content).setBackgroundColor(themeBackgroundColor)
        playerView.setBackgroundColor(themeBackgroundColor)
        playerView.setShutterBackgroundColor(themeBackgroundColor)

        val density = resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density).toInt().coerceAtLeast(1)
        val compact = resources.configuration.screenWidthDp < 720 ||
            resources.configuration.screenHeightDp < 480
        playerView.findViewById<View>(androidx.media3.ui.R.id.exo_bottom_bar).background =
            roundedThemeDrawable(
                colorWithAlpha(themeSurfaceColor, 0xD6),
                if (compact) 12f else 16f,
                dp(1.4f),
                colorWithAlpha(themeAccentColor, 0xC7),
            )

        val neutralControls = listOf(
            R.id.tetotv_rewind_control,
            R.id.tetotv_fast_forward_control,
            R.id.tetotv_audio_control,
            R.id.tetotv_caption_control,
            R.id.tetotv_caption_size_control,
            R.id.tetotv_picture_control,
            R.id.tetotv_player_control,
            R.id.tetotv_sources_control,
            R.id.tetotv_options_control,
        )
        neutralControls.forEach { id ->
            playerView.findViewById<View>(id)?.background = themedControlBackground(primary = false)
        }
        playerView.findViewById<View>(R.id.tetotv_play_pause_control).background =
            themedControlBackground(primary = true)

        playerView.findViewById<View>(R.id.tetotv_player_controls_scroll)
            .applyThemeForeground(themePrimaryTextColor)
        // The Play/Pause pill is accent-filled. Re-apply a contrast-aware
        // foreground after the neutral action row receives primaryText.
        playerView.findViewById<View>(R.id.tetotv_play_pause_control)
            .applyThemeForeground(
                nativeThemeAccentForeground(
                    hasCustomTheme = true,
                    accent = themeAccentColor,
                    legacyForeground = themePrimaryTextColor,
                ),
            )
        playerView.findViewById<View>(R.id.tetotv_time_footer)
            .applyThemeForeground(themePrimaryTextColor)
        playerView.findViewById<TextView>(R.id.tetotv_controller_title)
            .setTextColor(themePrimaryTextColor)
        playerView.findViewById<TextView>(R.id.tetotv_paused_title)
            .setTextColor(themePrimaryTextColor)
        playerView.findViewById<TextView>(R.id.tetotv_footer_hint)
            .setTextColor(themeMutedTextColor)

        listOf(R.id.tetotv_engine_label, R.id.tetotv_stream_label).forEach { id ->
            playerView.findViewById<TextView>(id)?.apply {
                setTextColor(themeAccentBrightColor)
                background = roundedThemeDrawable(
                    colorWithAlpha(themeAccentColor, 0x33),
                    999f,
                    dp(1f),
                    colorWithAlpha(themeAccentColor, 0x59),
                )
            }
        }
        playerView.findViewById<DefaultTimeBar>(androidx.media3.ui.R.id.exo_progress).apply {
            setPlayedColor(themeAccentBrightColor)
            setBufferedColor(colorWithAlpha(themePrimaryTextColor, 0x3D))
            setUnplayedColor(colorWithAlpha(themePrimaryTextColor, 0x3D))
            setScrubberColor(Color.TRANSPARENT)
        }
        skipSegmentButton.apply {
            setTextColor(themePrimaryTextColor)
            background = themedSkipBackground()
            compoundDrawablesRelative.forEach { it?.mutate()?.setTint(themePrimaryTextColor) }
        }
    }

    private fun View.applyThemeForeground(color: Int) {
        when (this) {
            is ImageButton -> imageTintList = ColorStateList.valueOf(color)
            is TextView -> setTextColor(color)
            is ViewGroup -> {
                for (index in 0 until childCount) getChildAt(index).applyThemeForeground(color)
            }
        }
    }

    private fun themedControlBackground(primary: Boolean): StateListDrawable {
        val density = resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density).toInt().coerceAtLeast(1)
        val neutral = blendThemeColors(themeSurfaceColor, themePrimaryTextColor, 0.10f)
        val base = if (primary) themeAccentColor else colorWithAlpha(neutral, 0x8F)
        val pressed = if (primary) {
            blendThemeColors(themeAccentColor, Color.BLACK, 0.14f)
        } else {
            blendThemeColors(neutral, themePrimaryTextColor, 0.10f)
        }
        val keyline = colorWithAlpha(nativeThemeContrastForeground(themeAccentColor), 0xE6)
        val focused = LayerDrawable(
            arrayOf(
                roundedThemeDrawable(colorWithAlpha(themeFocusColor, 0x99), 8f),
                roundedThemeDrawable(base, 7f, dp(3f), themeFocusColor),
                roundedThemeDrawable(base, 4f, dp(1f), keyline),
            ),
        ).apply {
            setLayerInset(1, dp(1f), dp(1f), dp(1f), dp(1f))
            setLayerInset(2, dp(4f), dp(4f), dp(4f), dp(4f))
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_activated), focused)
            addState(intArrayOf(android.R.attr.state_pressed), roundedThemeDrawable(pressed, 8f))
            addState(intArrayOf(), roundedThemeDrawable(base, 8f))
        }
    }

    private fun themedSkipBackground(): StateListDrawable {
        val density = resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density).toInt().coerceAtLeast(1)
        val base = colorWithAlpha(themeSurfaceColor, 0xB3)
        val focused = LayerDrawable(
            arrayOf(
                roundedThemeDrawable(colorWithAlpha(themeFocusColor, 0x66), 12f),
                roundedThemeDrawable(base, 10f, dp(3f), themeFocusColor),
                roundedThemeDrawable(Color.TRANSPARENT, 7f, dp(1f),
                    colorWithAlpha(nativeThemeContrastForeground(themeAccentColor), 0xE6)),
            ),
        ).apply {
            setLayerInset(1, dp(2f), dp(2f), dp(2f), dp(2f))
            setLayerInset(2, dp(5f), dp(5f), dp(5f), dp(5f))
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_focused), focused)
            addState(
                intArrayOf(android.R.attr.state_pressed),
                roundedThemeDrawable(blendThemeColors(themeAccentColor, Color.BLACK, 0.18f), 10f),
            )
            addState(
                intArrayOf(),
                roundedThemeDrawable(
                    base,
                    10f,
                    dp(1f),
                    colorWithAlpha(themeAccentBrightColor, 0xD1),
                ),
            )
        }
    }

    private fun themedDialogButtonBackground(danger: Boolean): StateListDrawable {
        val density = resources.displayMetrics.density
        fun dp(value: Float): Int = (value * density).toInt().coerceAtLeast(1)
        val neutral = blendThemeColors(themeSurfaceColor, themePrimaryTextColor, 0.12f)
        val base = if (danger) themeAccentColor else neutral
        val focusedBase = blendThemeColors(base, themePrimaryTextColor, 0.08f)
        val pressed = blendThemeColors(base, Color.BLACK, 0.15f)
        return StateListDrawable().apply {
            addState(
                intArrayOf(android.R.attr.state_focused),
                roundedThemeDrawable(focusedBase, 10f, dp(3f), themeFocusColor),
            )
            addState(
                intArrayOf(android.R.attr.state_pressed),
                roundedThemeDrawable(pressed, 10f),
            )
            addState(
                intArrayOf(),
                roundedThemeDrawable(
                    base,
                    10f,
                    dp(1f),
                    colorWithAlpha(themePrimaryTextColor, if (danger) 0x77 else 0x55),
                ),
            )
        }
    }

    private fun roundedThemeDrawable(
        color: Int,
        radiusDp: Float,
        strokeWidth: Int = 0,
        strokeColor: Int = Color.TRANSPARENT,
    ): GradientDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(color)
        cornerRadius = radiusDp * resources.displayMetrics.density
        if (strokeWidth > 0) setStroke(strokeWidth, strokeColor)
    }

    private fun colorWithAlpha(color: Int, alpha: Int): Int = Color.argb(
        alpha.coerceIn(0, 255),
        Color.red(color),
        Color.green(color),
        Color.blue(color),
    )

    private fun blendThemeColors(first: Int, second: Int, amount: Float): Int {
        val t = amount.coerceIn(0f, 1f)
        fun blend(start: Int, end: Int): Int = (start + (end - start) * t).toInt()
        return Color.rgb(
            blend(Color.red(first), Color.red(second)),
            blend(Color.green(first), Color.green(second)),
            blend(Color.blue(first), Color.blue(second)),
        )
    }

    /** Match the responsive insets and 1280dp width cap used by Flutter chrome. */
    private fun configurePlayerChromeBounds() {
        val card = playerView.findViewById<View>(androidx.media3.ui.R.id.exo_bottom_bar) ?: return
        val density = resources.displayMetrics.density
        val compact = resources.configuration.screenWidthDp < 720 ||
            resources.configuration.screenHeightDp < 480
        fun dp(value: Int): Int = (value * density).toInt()

        val horizontalInset = dp(if (compact) 12 else 28)
        val availableWidth = resources.displayMetrics.widthPixels - (horizontalInset * 2)
        (card.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
            params.width = min(availableWidth.coerceAtLeast(1), dp(1_280))
            params.leftMargin = horizontalInset
            params.rightMargin = horizontalInset
            params.bottomMargin = dp(if (compact) 10 else 24)
            params.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            card.layoutParams = params
        }
        card.setPadding(
            dp(if (compact) 12 else 18),
            dp(if (compact) 10 else 14),
            dp(if (compact) 12 else 18),
            dp(if (compact) 9 else 12),
        )
        playerView.findViewById<View>(R.id.tetotv_engine_label).visibility =
            if (compact) View.GONE else View.VISIBLE
        playerView.findViewById<View>(R.id.tetotv_footer_hint).visibility =
            if (compact) View.GONE else View.VISIBLE
        // Keep the fixed 40dp HUD pills stable when Android's system font scale
        // is large. The focused icon remains the accessible control surface,
        // while these short visual labels stay on one line inside the pill.
        playerView.findViewById<View>(R.id.tetotv_player_controls_scroll)
            .applyTvSafeActionLabelTextSize(
                tvSafeHudTextSizePx(HUD_ACTION_LABEL_SIZE_DP),
            )
        if (compact) {
            // Mirror TetoPlayerChrome's compact (<720x480) tokens. Media3 owns
            // a native hierarchy, so these values are applied at runtime.
            playerView.findViewById<TextView>(R.id.tetotv_controller_title)
                .setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            (card.background?.mutate() as? GradientDrawable)?.cornerRadius = dp(12).toFloat()
            playerView.findViewById<View>(R.id.tetotv_player_controls_scroll)
                .setTopMargin(dp(7))
            listOf(
                androidx.media3.ui.R.id.exo_position,
                androidx.media3.ui.R.id.exo_duration,
            ).forEach { id ->
                playerView.findViewById<TextView>(id)
                    .setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
            }
        }
    }

    private fun View.applyTvSafeActionLabelTextSize(textSizePx: Float) {
        when (this) {
            is TextView -> {
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                setTextSize(TypedValue.COMPLEX_UNIT_PX, textSizePx)
            }
            is ViewGroup -> {
                for (index in 0 until childCount) {
                    getChildAt(index).applyTvSafeActionLabelTextSize(textSizePx)
                }
            }
        }
    }

    private fun tvSafeHudTextSizePx(textSizeDp: Float): Float =
        textSizeDp * resources.displayMetrics.density *
            resources.configuration.fontScale.coerceAtMost(HUD_MAX_TEXT_SCALE)

    private fun View.setTopMargin(margin: Int) {
        (layoutParams as? ViewGroup.MarginLayoutParams)?.let { params ->
            params.topMargin = margin
            layoutParams = params
        }
    }

    /** Keep the native skip action aligned with the immutable MPV HUD. */
    private fun updateSkipSegmentButtonPosition(controllerVisible: Boolean) {
        if (!::skipSegmentButton.isInitialized) return
        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()
        val compact = resources.configuration.screenWidthDp < 720 ||
            resources.configuration.screenHeightDp < 480
        (skipSegmentButton.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
            params.marginEnd = dp(if (compact) 16 else 38)
            params.bottomMargin = dp(
                if (controllerVisible) {
                    if (compact) 132 else 184
                } else {
                    26
                },
            )
            params.gravity = Gravity.END or Gravity.BOTTOM
            skipSegmentButton.layoutParams = params
        }
    }

    /** Let phone users tap the whole pill while D-pad focus stays on its icon. */
    private fun bindChromeControlSurface(containerId: Int, controlId: Int) {
        val container = playerView.findViewById<View>(containerId) ?: return
        val control = playerView.findViewById<View>(controlId) ?: return
        container.setOnClickListener { control.performClick() }
        // The pill is the visual surface, but the child icon owns
        // accessibility and D-pad focus. Mirror that focus explicitly so the
        // parent selector always renders the Teto focus ring on Android TV.
        val existingFocusListener = control.onFocusChangeListener
        control.setOnFocusChangeListener { view, hasFocus ->
            existingFocusListener?.onFocusChange(view, hasFocus)
            setChromeControlHighlighted(container, hasFocus)
            if (hasFocus) {
                container.post {
                    if (controlId == R.id.tetotv_player_options) {
                        playerView
                            .findViewById<HorizontalScrollView>(R.id.tetotv_player_controls_scroll)
                            ?.fullScroll(View.FOCUS_RIGHT)
                    }
                    val revealInset =
                        (FOCUS_REVEAL_INSET_DP * resources.displayMetrics.density).toInt()
                    container.requestRectangleOnScreen(
                        Rect(-revealInset, 0, container.width + revealInset, container.height),
                        true,
                    )
                }
            }
        }
        val touchListener = View.OnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> setChromeControlHighlighted(container, true)
                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_CANCEL,
                -> setChromeControlHighlighted(container, control.hasFocus())
            }
            false
        }
        container.setOnTouchListener(touchListener)
        control.setOnTouchListener(touchListener)
        setChromeControlHighlighted(container, control.hasFocus(), animate = false)
    }

    private fun setChromeControlHighlighted(
        container: View,
        highlighted: Boolean,
        animate: Boolean = true,
    ) {
        container.isActivated = highlighted
        container.animate().cancel()
        if (!animate) {
            val scale = if (highlighted) CHROME_FOCUS_SCALE else 1f
            container.scaleX = scale
            container.scaleY = scale
            return
        }
        container.animate()
            .scaleX(if (highlighted) CHROME_FOCUS_SCALE else 1f)
            .scaleY(if (highlighted) CHROME_FOCUS_SCALE else 1f)
            .setDuration(CHROME_FOCUS_ANIMATION_MS)
            .setInterpolator(CHROME_FOCUS_INTERPOLATOR)
            .start()
    }

    private fun updateTransportControlAvailability(commands: Player.Commands) {
        if (
            !::rewindControlContainer.isInitialized ||
            !::playPauseControlContainer.isInitialized ||
            !::fastForwardControlContainer.isInitialized
        ) return
        setChromeControlAvailable(
            rewindControlContainer,
            commands.contains(Player.COMMAND_SEEK_BACK),
        )
        setChromeControlAvailable(
            playPauseControlContainer,
            commands.contains(Player.COMMAND_PLAY_PAUSE),
        )
        setChromeControlAvailable(
            fastForwardControlContainer,
            commands.contains(Player.COMMAND_SEEK_FORWARD),
        )
    }

    private fun setChromeControlAvailable(container: View, available: Boolean) {
        container.isEnabled = available
        container.isClickable = available
        container.alpha = if (available) 1f else DISABLED_CONTROL_ALPHA
    }

    private fun publishDiscordPresence() {
        if (suppressDiscordPresence || !::player.isInitialized || resultSent) return
        DiscordRichPresenceBridge.updatePlayback(
            title = displayTitle,
            episode = episodeNumber,
            playing = isPlaybackIntended(),
            positionMs = safePositionMs(),
            durationMs = safeDurationMs(),
            artworkUrl = artworkUrl,
        )
    }

    private fun fetchSkipSegmentsIfReady() {
        if (
            skipFetchComplete ||
            skipFetchInFlight ||
            skipFetchAttempts >= MAX_SKIP_FETCH_ATTEMPTS ||
            malMediaId <= 0 ||
            episodeNumber <= 0
        ) return
        val durationMs = safeDurationMs()
        if (durationMs <= 0L) return
        if (abs(durationMs - skipDurationCandidateMs) > SKIP_DURATION_STABILITY_TOLERANCE_MS) {
            skipDurationCandidateMs = durationMs
            handler.removeCallbacks(skipDurationStabilityRunnable)
            if (isForeground) {
                handler.postDelayed(
                    skipDurationStabilityRunnable,
                    SKIP_DURATION_STABILITY_DELAY_MS,
                )
            }
            return
        }
        skipFetchInFlight = true
        skipFetchAttempts++
        val episodeLength = durationMs / 1_000.0
        val url = buildString {
            append("https://api.aniskip.com/v2/skip-times/")
            append(malMediaId)
            append('/')
            append(episodeNumber)
            append("?types%5B%5D=op&types%5B%5D=ed")
            append("&types%5B%5D=mixed-op&types%5B%5D=mixed-ed")
            append("&types%5B%5D=recap")
            append("&episodeLength=")
            append(episodeLength)
        }
        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("User-Agent", "TetoTV/1.9 AndroidTV Media3")
            .build()
        metadataClient.newCall(request).enqueue(
            object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    handler.post {
                        if (resultSent || isFinishing || isDestroyed) return@post
                        skipFetchInFlight = false
                        scheduleSkipFetchRetry()
                    }
                }

                override fun onResponse(call: Call, response: Response) {
                    response.use {
                        val successful = response.isSuccessful
                        val retryableStatus = response.code == 429 || response.code >= 500
                        val parsed = if (successful) {
                            val body = response.body
                            val contentLength = body?.contentLength() ?: 0L
                            val payload = runCatching {
                                body?.source()?.let { source ->
                                    if (contentLength > MAX_SKIP_RESPONSE_BYTES) {
                                        null
                                    } else {
                                        source.request(MAX_SKIP_RESPONSE_BYTES + 1L)
                                        if (source.buffer.size > MAX_SKIP_RESPONSE_BYTES) {
                                            null
                                        } else {
                                            source.buffer.clone().readUtf8()
                                        }
                                    }
                                }
                            }.getOrNull()
                            payload?.let {
                                runCatching { parseSkipSegments(it, durationMs) }.getOrNull()
                            }
                        } else {
                            null
                        }
                        handler.post {
                            if (resultSent || isFinishing || isDestroyed) return@post
                            skipFetchInFlight = false
                            if (
                                abs(safeDurationMs() - durationMs) >
                                SKIP_DURATION_STABILITY_TOLERANCE_MS
                            ) {
                                skipFetchAttempts = (skipFetchAttempts - 1).coerceAtLeast(0)
                                skipDurationCandidateMs = safeDurationMs()
                                handler.removeCallbacks(skipDurationStabilityRunnable)
                                if (isForeground) {
                                    handler.postDelayed(
                                        skipDurationStabilityRunnable,
                                        SKIP_DURATION_STABILITY_DELAY_MS,
                                    )
                                }
                                return@post
                            }
                            when {
                                successful && parsed != null -> {
                                    skipFetchComplete = true
                                    skipSegments.clear()
                                    skipSegments.addAll(parsed)
                                    updateSkipSegmentButton()
                                }
                                retryableStatus || successful -> scheduleSkipFetchRetry()
                                else -> skipFetchComplete = true
                            }
                        }
                    }
                }
            },
        )
    }

    private fun scheduleSkipFetchRetry() {
        if (skipFetchAttempts >= MAX_SKIP_FETCH_ATTEMPTS) {
            skipFetchComplete = true
            return
        }
        handler.removeCallbacks(skipFetchRetryRunnable)
        handler.removeCallbacks(skipDurationStabilityRunnable)
        if (!isForeground) return
        handler.postDelayed(
            skipFetchRetryRunnable,
            SKIP_FETCH_RETRY_BASE_MS * skipFetchAttempts,
        )
    }

    private fun parseSkipSegments(payload: String, durationMs: Long): List<NativeSkipSegment> {
        val results = JSONObject(payload).optJSONArray("results") ?: return emptyList()
        val episodeLengthSeconds = durationMs / 1_000.0
        return buildList {
            for (index in 0 until results.length()) {
                val item = results.optJSONObject(index) ?: continue
                val interval = item.optJSONObject("interval") ?: continue
                val startMs = (interval.optDouble("startTime", -1.0) * 1_000).toLong()
                val endMs = (interval.optDouble("endTime", -1.0) * 1_000).toLong()
                val referenceLength = item.optDouble("episodeLength", episodeLengthSeconds)
                val durationTolerance = max(45.0, episodeLengthSeconds * 0.05)
                if (abs(referenceLength - episodeLengthSeconds) > durationTolerance) continue
                val clampedStart = startMs.coerceIn(0L, durationMs)
                val clampedEnd = endMs.coerceIn(0L, durationMs)
                val length = clampedEnd - clampedStart
                if (length !in MIN_SKIP_SEGMENT_MS..MAX_SKIP_SEGMENT_MS) continue
                val kind = when (item.optString("skipType").lowercase()) {
                    "op", "mixed-op", "opening", "intro" -> "opening"
                    "ed", "mixed-ed", "ending", "outro" -> "ending"
                    "recap" -> "recap"
                    else -> continue
                }
                add(NativeSkipSegment(clampedStart, clampedEnd, kind))
            }
        }.sortedBy(NativeSkipSegment::startMs)
    }

    private fun updateSkipSegmentButton() {
        if (
            resultSent ||
            playbackResourcesReleased ||
            !::skipSegmentButton.isInitialized ||
            !::player.isInitialized
        ) return
        val position = safePositionMs()
        val active = activeNativeSkipSegment(position, skipSegments, autoSkippedSegments)
        if (active == activeSkipSegment) return
        activeSkipSegment = active
        if (active != null) {
            val autoSkip =
                (active.kind == "opening" && autoSkipIntros) ||
                    (active.kind == "ending" && autoSkipOutros)
            val key = nativeSkipSegmentKey(active)
            if (autoSkip && autoSkippedSegments.add(key)) {
                seekPastSkipSegment(active, announce = true)
                return
            }
        }
        skipSegmentButton.visibility = if (active == null) View.GONE else View.VISIBLE
        if (active != null) {
            skipSegmentButton.setText(
                when (active.kind) {
                    "ending" -> R.string.tetotv_player_skip_outro
                    "recap" -> R.string.tetotv_player_skip_recap
                    else -> R.string.tetotv_player_skip_intro
                },
            )
            val focusKey = nativeSkipSegmentKey(active)
            if (
                autoFocusedSkipSegments.add(focusKey) &&
                !playerView.isControllerFullyVisible
            ) {
                // Never steal focus from a viewer already operating the HUD.
                // When playback is unobstructed, retain the MPV behavior of
                // focusing a newly available skip action once.
                skipSegmentButton.post { skipSegmentButton.requestFocus() }
            }
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        terminalError = buildString {
            append(error.errorCodeName)
            NetworkRequestPolicy.redactNetworkDiagnostic(error.message)?.let {
                append(": $it")
            }
            error.cause?.let { cause ->
                append(" (${cause.javaClass.simpleName}")
                NetworkRequestPolicy.redactNetworkDiagnostic(cause.message)?.let {
                    append(": $it")
                }
                append(')')
            }
        }
        finishWithResult(STATUS_ERROR)
    }

    override fun onRenderedFirstFrame() {
        firstFrameRendered = true
        everFirstFrameRendered = true
        resetDropWindow()
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        // Reading this callback forces Media3 to validate the video renderer,
        // while onRenderedFirstFrame remains the authoritative display signal.
        if (videoSize.width <= 0 || videoSize.height <= 0) return
    }

    override fun onTracksChanged(tracks: Tracks) {
        val audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        if (
            audioGroups.isNotEmpty() &&
            audioGroups.none { group ->
                (0 until group.length).any(group::isTrackSupported)
            }
        ) {
            terminalError = "Media3 found audio tracks but no supported audio decoder."
            finishWithResult(STATUS_ERROR)
            return
        }
        applyPreferredAudioOverride(tracks)
        applyPreferredSubtitleOverride(tracks)
        updateTrackButtons(tracks)
        if (
            isForeground &&
            player.playbackState == Player.STATE_READY &&
            !firstFrameRendered &&
            hasSelectedVideoTrack()
        ) {
            handler.removeCallbacks(firstFrameWatchdog)
            handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
        }
    }

    private fun applyPreferredSubtitleOverride(tracks: Tracks) {
        if (preferredSubtitleOverrideApplied || !subtitlesEnabled) return
        val preferredTags = preferredLanguageTags(preferredSubtitleLanguage).toSet()
        val normalizedPreference = preferredSubtitleLanguage.trim().lowercase()
        var bestGroup: Tracks.Group? = null
        var bestTrack = -1
        var bestScore = Int.MIN_VALUE
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_TEXT) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                val language = format.language.orEmpty().lowercase()
                val label = format.label.orEmpty().lowercase()
                val description = "$language $label"
                var score = 0
                if (language in preferredTags) score += 140
                if (normalizedPreference in description) score += 80
                if (
                    normalizedPreference in setOf("eng", "en", "english") &&
                    ("english" in description || "eng " in description)
                ) score += 120
                if (format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0) score += 15
                if ("full" in description || "dialogue" in description) score += 30
                if ("closed caption" in description || "cc" in label || "sdh" in label) score += 20
                if (format.selectionFlags and C.SELECTION_FLAG_FORCED != 0) score -= 100
                if ("sign" in description || "song" in description || "forced" in description) {
                    score -= 100
                }
                if (score > bestScore) {
                    bestScore = score
                    bestGroup = group
                    bestTrack = index
                }
            }
        }
        val group = bestGroup ?: return
        if (bestTrack < 0 || bestScore < 50) return
        // Set the guard before changing parameters because that change can
        // synchronously result in another onTracksChanged callback.
        preferredSubtitleOverrideApplied = true
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, bestTrack))
            .build()
    }

    private fun updateTrackButtons(tracks: Tracks) {
        if (!::audioTrackButton.isInitialized || !::captionTrackButton.isInitialized) return
        // Keep the same explanatory behavior as MPV/VLC. A viewer may open an
        // unavailable picker and receive the engine's "no tracks" message;
        // silently dimming/removing focus made the native HUD feel different.
        audioTrackButton.isEnabled = true
        audioTrackButton.alpha = 1f
        setChromeControlAvailable(audioControlContainer, true)
        captionTrackButton.isEnabled = true
        captionTrackButton.alpha = 1f
        setChromeControlAvailable(captionControlContainer, true)
        val captionsSelected = tracks.groups.any { group ->
            group.type == C.TRACK_TYPE_TEXT && group.isSelected
        }
        captionTrackButton.isSelected = captionsSelected
        // TetoPlayerChrome intentionally uses one stable CC glyph; state is
        // communicated by the description and picker selection instead.
        captionTrackButton.setImageResource(R.drawable.tetotv_ic_subtitle_on)
        captionTrackButton.contentDescription = getString(
            if (captionsSelected) {
                R.string.tetotv_player_closed_captions_on
            } else {
                R.string.tetotv_player_closed_captions_off
            },
        )
    }

    private fun supportedTrackCount(trackType: Int): Int =
        player.currentTracks.groups
            .filter { it.type == trackType }
            .sumOf { group -> (0 until group.length).count(group::isTrackSupported) }

    private fun showTrackPicker(trackType: Int, sourceButton: View) {
        if (trackType == C.TRACK_TYPE_AUDIO && supportedTrackCount(trackType) < 2) {
            val advertised = nativeReleaseAdvertisesMultipleAudio(
                intent.getStringExtra(EXTRA_FILE_NAME),
            )
            waitForAudioTracks(
                sourceButton,
                if (advertised) AUDIO_TRACK_ADVERTISED_WAIT_MS else AUDIO_TRACK_DEFAULT_WAIT_MS,
                warnIfSingle = advertised,
            )
            return
        }
        showTrackPickerNow(trackType, sourceButton)
    }

    private fun waitForAudioTracks(
        sourceButton: View,
        maximumWaitMs: Long,
        warnIfSingle: Boolean,
    ) {
        if (pendingAudioTrackPicker != null) return
        handler.removeCallbacks(hideControllerRunnable)
        Toast.makeText(
            this,
            R.string.tetotv_player_checking_audio_tracks,
            Toast.LENGTH_SHORT,
        ).show()
        val startedAt = SystemClock.uptimeMillis()
        val task = object : Runnable {
            override fun run() {
                if (resultSent || playerCoreReleased || isFinishing || isDestroyed) {
                    pendingAudioTrackPicker = null
                    return
                }
                val trackCount = supportedTrackCount(C.TRACK_TYPE_AUDIO)
                val timedOut = SystemClock.uptimeMillis() - startedAt >= maximumWaitMs
                if (trackCount >= 2 || timedOut) {
                    pendingAudioTrackPicker = null
                    if (timedOut && trackCount < 2 && warnIfSingle) {
                        Toast.makeText(
                            this@Media3PlayerActivity,
                            R.string.tetotv_player_dual_audio_single_track,
                            Toast.LENGTH_LONG,
                        ).show()
                    }
                    showTrackPickerNow(C.TRACK_TYPE_AUDIO, sourceButton)
                } else {
                    handler.postDelayed(this, AUDIO_TRACK_POLL_MS)
                }
            }
        }
        pendingAudioTrackPicker = task
        handler.postDelayed(task, AUDIO_TRACK_POLL_MS)
    }

    private fun showTrackPickerNow(trackType: Int, sourceButton: View) {
        val selectableTracks = player.currentTracks.groups.any { group ->
            group.type == trackType &&
                (0 until group.length).any(group::isTrackSupported)
        }
        if (!selectableTracks) {
            val message = if (trackType == C.TRACK_TYPE_AUDIO) {
                R.string.tetotv_player_no_audio_tracks
            } else {
                R.string.tetotv_player_no_caption_tracks
            }
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
            armControllerAutoHide()
            return
        }

        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val title = if (trackType == C.TRACK_TYPE_AUDIO) {
            R.string.tetotv_player_select_audio
        } else {
            R.string.tetotv_player_select_captions
        }
        val audioSelectionParametersBefore = if (trackType == C.TRACK_TYPE_AUDIO) {
            player.trackSelectionParameters
        } else {
            null
        }
        try {
            val dialog = TrackSelectionDialogBuilder(this, getString(title), player, trackType)
                .setTheme(R.style.NativePlayerTrackDialogTheme)
                .setAllowAdaptiveSelections(false)
                .setAllowMultipleOverrides(false)
                .setShowDisableOption(trackType == C.TRACK_TYPE_TEXT)
                .build()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                var audioSelectionChanged = false
                if (
                    trackType == C.TRACK_TYPE_AUDIO &&
                    player.trackSelectionParameters != audioSelectionParametersBefore
                ) {
                    audioSelectionChanged = true
                    audioPreferenceChanged = true
                    // A viewer's explicit choice owns the remainder of this
                    // session, even if the demuxer publishes another snapshot.
                    preferredAudioOverrideApplied = true
                }
                if (activeTrackDialog === dialog) activeTrackDialog = null
                consumedNavigationKeyUp = null
                if (!isFinishing && !isDestroyed) {
                    if (!audioSelectionChanged) {
                        // Track updates are intentionally ignored while the
                        // picker is open so they cannot replace a viewer's
                        // selection. Reconsider the latest snapshot if the
                        // picker was dismissed without changing anything.
                        applyPreferredAudioOverride(player.currentTracks)
                    }
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun showSubtitleSizePicker(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val values = SUBTITLE_SIZE_VALUES
        val labels = arrayOf(
            getString(R.string.tetotv_player_caption_size_small),
            getString(R.string.tetotv_player_caption_size_medium),
            getString(R.string.tetotv_player_caption_size_large),
            getString(R.string.tetotv_player_caption_size_extra_large),
        )
        val selectedIndex = values.indices.minByOrNull { index ->
            abs(values[index] - subtitleSize)
        } ?: 1
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle(R.string.tetotv_player_select_caption_size)
                .setSingleChoiceItems(labels, selectedIndex) { picker, index ->
                    subtitleSize = values[index]
                    applySubtitleStyle()
                    Toast.makeText(
                        this,
                        getString(
                            R.string.tetotv_player_caption_size_changed,
                            labels[index],
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    picker.dismiss()
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                consumedNavigationKeyUp = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun showSubtitleBackgroundPicker(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val labels = arrayOf(
            getString(R.string.tetotv_player_caption_background_transparent),
            getString(R.string.tetotv_player_caption_background_dark),
            getString(R.string.tetotv_player_caption_background_high_contrast),
        )
        val selectedIndex = when {
            highContrastSubtitles -> 2
            Color.alpha(subtitleBackgroundColor) == 0 -> 0
            else -> 1
        }
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle(R.string.tetotv_player_caption_background)
                .setSingleChoiceItems(labels, selectedIndex) { picker, index ->
                    when (index) {
                        0 -> {
                            highContrastSubtitles = false
                            subtitleBackgroundColor = Color.TRANSPARENT
                        }
                        1 -> {
                            highContrastSubtitles = false
                            subtitleBackgroundColor = CAPTION_DARK_BACKGROUND
                        }
                        else -> {
                            highContrastSubtitles = true
                            subtitleBackgroundColor = CAPTION_HIGH_CONTRAST_BACKGROUND
                        }
                    }
                    applySubtitleStyle()
                    Toast.makeText(
                        this,
                        getString(
                            R.string.tetotv_player_caption_background_changed,
                            labels[index],
                        ),
                        Toast.LENGTH_SHORT,
                    ).show()
                    picker.dismiss()
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                consumedNavigationKeyUp = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun cyclePictureMode(sourceButton: View) {
        videoResizeMode = when (videoResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_FIT ->
                AspectRatioFrameLayout.RESIZE_MODE_ZOOM
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM ->
                AspectRatioFrameLayout.RESIZE_MODE_FILL
            else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
        playerView.resizeMode = videoResizeMode
        val label = when (videoResizeMode) {
            AspectRatioFrameLayout.RESIZE_MODE_ZOOM -> "Fill screen"
            AspectRatioFrameLayout.RESIZE_MODE_FILL -> "Stretch"
            else -> "Fit"
        }
        Toast.makeText(this, "Picture: $label", Toast.LENGTH_SHORT).show()
        playerView.showController()
        sourceButton.requestFocus()
        armControllerAutoHide()
    }

    private fun showPlaybackOptions(sourceButton: View) {
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val labels = arrayOf(
            "Picture mode",
            "Audio tracks",
            "Closed captions",
            "Caption size",
            getString(R.string.tetotv_player_caption_background),
            "Choose player",
        )
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle(R.string.tetotv_player_options)
                .setItems(labels) { picker, index ->
                    picker.dismiss()
                    handler.post {
                        when (index) {
                            0 -> cyclePictureMode(sourceButton)
                            1 -> showTrackPicker(C.TRACK_TYPE_AUDIO, audioTrackButton)
                            2 -> showTrackPicker(C.TRACK_TYPE_TEXT, captionTrackButton)
                            3 -> showSubtitleSizePicker(captionSizeButton)
                            4 -> showSubtitleBackgroundPicker(sourceButton)
                            5 -> showPlayerPicker(sourceButton)
                        }
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                consumedNavigationKeyUp = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun showPlayerPicker(sourceButton: View) {
        if (suppressDiscordPresence) {
            Toast.makeText(
                this,
                R.string.tetotv_player_local_media3_only,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
            return
        }
        handler.removeCallbacks(hideControllerRunnable)
        activeTrackDialog?.dismiss()
        val labels = arrayOf(
            "Media3 - current",
            "MPV - best for subtitles and web streams",
            "VLC - compatibility player",
        )
        try {
            val dialog = AlertDialog.Builder(this, R.style.NativePlayerTrackDialogTheme)
                .setTitle("Choose player")
                .setSingleChoiceItems(labels, 0) { picker, index ->
                    picker.dismiss()
                    when (index) {
                        1 -> {
                            persistCheckpoint()
                            finishWithResult(STATUS_USE_MPV)
                        }
                        2 -> {
                            persistCheckpoint()
                            finishWithResult(STATUS_USE_VLC)
                        }
                        else -> {
                            playerView.showController()
                            sourceButton.requestFocus()
                            armControllerAutoHide()
                        }
                    }
                }
                .setNegativeButton(android.R.string.cancel, null)
                .create()
            activeTrackDialog = dialog
            dialog.setOnDismissListener {
                if (activeTrackDialog === dialog) activeTrackDialog = null
                consumedNavigationKeyUp = null
                if (!isFinishing && !isDestroyed) {
                    playerView.showController()
                    sourceButton.requestFocus()
                    armControllerAutoHide()
                }
            }
            dialog.show()
        } catch (_: Throwable) {
            activeTrackDialog = null
            Toast.makeText(
                this,
                R.string.tetotv_player_track_picker_error,
                Toast.LENGTH_SHORT,
            ).show()
            playerView.showController()
            sourceButton.requestFocus()
            armControllerAutoHide()
        }
    }

    private fun applySubtitleStyle() {
        playerView.subtitleView?.apply {
            val customCaptionColors =
                subtitleTextColor != Color.WHITE || subtitleBackgroundColor != Color.TRANSPARENT
            setApplyEmbeddedStyles(!highContrastSubtitles && !customCaptionColors)
            setApplyEmbeddedFontSizes(
                !highContrastSubtitles && !customCaptionColors &&
                    subtitleSize == DEFAULT_SUBTITLE_SIZE,
            )
            setFixedTextSize(TypedValue.COMPLEX_UNIT_SP, subtitleSize)
            setBottomPaddingFraction((108 - subtitlePosition) / 100f)
            if (highContrastSubtitles || customCaptionColors) {
                setStyle(
                    CaptionStyleCompat(
                        subtitleTextColor,
                        if (highContrastSubtitles) 0xDD000000.toInt()
                        else subtitleBackgroundColor,
                        Color.TRANSPARENT,
                        CaptionStyleCompat.EDGE_TYPE_OUTLINE,
                        Color.BLACK,
                        null,
                    ),
                )
            } else {
                // Explicitly clear a style applied by a prior in-player
                // selection. Merely re-enabling embedded styles leaves the
                // old CaptionStyleCompat background attached to SubtitleView.
                setStyle(CaptionStyleCompat.DEFAULT)
            }
        }
        updateCaptionSizeDescription()
    }

    private fun updateCaptionSizeDescription() {
        if (!::captionSizeButton.isInitialized) return
        val label = when (subtitleSize) {
            in 0f..30f -> getString(R.string.tetotv_player_caption_size_small)
            in 30f..38f -> getString(R.string.tetotv_player_caption_size_medium)
            in 38f..46f -> getString(R.string.tetotv_player_caption_size_large)
            else -> getString(R.string.tetotv_player_caption_size_extra_large)
        }
        captionSizeButton.contentDescription = getString(
            R.string.tetotv_player_caption_size_changed,
            label,
        )
    }

    private fun seekRelative(offsetMs: Long, sourceButton: View) {
        val duration = safeDurationMs()
        val candidate = safePositionMs() + offsetMs
        val target = when {
            candidate < 0L -> 0L
            duration > 0L && candidate > duration -> duration
            else -> candidate
        }
        player.seekTo(target)
        playerView.showController()
        sourceButton.requestFocus()
        armControllerAutoHide()
    }

    private fun seekPastSkipSegment(segment: NativeSkipSegment, announce: Boolean) {
        if (resultSent || playbackResourcesReleased || !::player.isInitialized) return
        val duration = safeDurationMs()
        val target = safeNativeSkipTargetMs(segment.endMs, duration)
        val segmentKey = nativeSkipSegmentKey(segment)
        val wasPlaying = player.playWhenReady
        autoSkippedSegments.add(segmentKey)
        activeSkipSegment = null
        skipSegmentButton.visibility = View.GONE
        if (playerView.isControllerFullyVisible) {
            requestTransportFocus()
            armControllerAutoHide()
        } else {
            playerView.requestFocus()
        }
        // Defer the seek until after the button callback and focus transition
        // have returned. This prevents an EOF completion callback from racing
        // view mutation or attempting native teardown twice.
        handler.post {
            if (resultSent || playbackResourcesReleased) return@post
            val seekSucceeded = runCatching { player.seekTo(target) }.isSuccess
            if (!seekSucceeded) {
                autoSkippedSegments.remove(segmentKey)
                updateSkipSegmentButton()
                Toast.makeText(this, "Could not skip this segment", Toast.LENGTH_SHORT).show()
            } else if (
                !wasPlaying &&
                segment.kind == "ending" &&
                nativeSkipReachesPlaybackEnd(segment.endMs, duration)
            ) {
                finishWithResult(STATUS_COMPLETED)
            } else if (announce) {
                Toast.makeText(
                    this,
                    if (segment.kind == "opening") "Intro skipped" else "Outro skipped",
                    Toast.LENGTH_SHORT,
                ).show()
            }
            if (seekSucceeded && !resultSent && !playbackResourcesReleased) {
                // Re-evaluate against every remaining segment. Consuming an
                // opening is keyed independently and cannot suppress a later
                // ending/outro action.
                updateSkipSegmentButton()
            }
        }
    }

    private fun showExitConfirmation() {
        if (exitDialog?.isShowing == true || isFinishing || isDestroyed) return
        // isPlaying is false while buffering even though playWhenReady is true.
        // Always pause so playback cannot start behind the confirmation dialog.
        val resumeAfterDialog = ::player.isInitialized && player.playWhenReady
        if (::player.isInitialized && !playbackResourcesReleased) {
            runCatching { player.pause() }
        }
        val dialog = AlertDialog.Builder(this, R.style.NativePlayerExitDialogTheme)
            .setTitle("Exit video?")
            .setMessage("Your current playback position will be saved.")
            .setCancelable(false)
            .setNegativeButton("Continue watching") { _, _ ->
                if (!isFinishing && !isDestroyed && !playbackResourcesReleased) {
                    if (resumeAfterDialog && ::player.isInitialized) {
                        runCatching { player.play() }
                    }
                    if (::playerView.isInitialized) {
                        playerView.showController()
                        requestTransportFocus()
                        armControllerAutoHide()
                    }
                }
            }
            .setPositiveButton("Exit video") { _, _ ->
                persistCheckpoint()
                finishWithResult(STATUS_STOPPED)
            }
            .create()
        exitDialog = dialog
        dialog.setOnDismissListener {
            if (exitDialog === dialog) exitDialog = null
        }
        dialog.setOnShowListener {
            val continueButton = dialog.getButton(AlertDialog.BUTTON_NEGATIVE)
            val exitButton = dialog.getButton(AlertDialog.BUTTON_POSITIVE)
            fun dp(value: Int): Int = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                value.toFloat(),
                resources.displayMetrics,
            ).toInt()
            val horizontalPadding = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                18f,
                resources.displayMetrics,
            ).toInt()
            val verticalPadding = TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP,
                11f,
                resources.displayMetrics,
            ).toInt()
            val dangerForeground = nativeThemeAccentForeground(
                hasCustomTheme = hasCustomNativeTheme,
                accent = themeAccentColor,
                legacyForeground = themePrimaryTextColor,
            )
            dialog.findViewById<TextView>(android.R.id.message)?.apply {
                setTextColor(themePrimaryTextColor)
                alpha = 0.92f
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
            }
            val alertTitleId = resources.getIdentifier("alertTitle", "id", "android")
            if (alertTitleId != 0) {
                dialog.findViewById<TextView>(alertTitleId)?.apply {
                    setTextColor(themePrimaryTextColor)
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
                    setTypeface(typeface, android.graphics.Typeface.BOLD)
                }
            }
            continueButton?.apply {
                isAllCaps = false
                setTextColor(themePrimaryTextColor)
                if (hasCustomNativeTheme) {
                    background = themedDialogButtonBackground(danger = false)
                } else {
                    setBackgroundResource(R.drawable.tetotv_dialog_neutral_button)
                }
                setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
                minimumHeight = dp(48)
                minHeight = dp(48)
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    R.drawable.tetotv_ic_play,
                    0,
                    0,
                    0,
                )
                compoundDrawablesRelative.forEach {
                    it?.mutate()?.setTint(themePrimaryTextColor)
                }
                compoundDrawablePadding = dp(8)
            }
            exitButton?.apply {
                isAllCaps = false
                setTextColor(dangerForeground)
                if (hasCustomNativeTheme) {
                    background = themedDialogButtonBackground(danger = true)
                } else {
                    setBackgroundResource(R.drawable.tetotv_dialog_danger_button)
                }
                setPadding(horizontalPadding, verticalPadding, horizontalPadding, verticalPadding)
                minimumHeight = dp(48)
                minHeight = dp(48)
                setCompoundDrawablesRelativeWithIntrinsicBounds(
                    R.drawable.tetotv_ic_exit,
                    0,
                    0,
                    0,
                )
                compoundDrawablesRelative.forEach {
                    it?.mutate()?.setTint(dangerForeground)
                }
                compoundDrawablePadding = dp(8)
            }
            (continueButton?.layoutParams as? ViewGroup.MarginLayoutParams)?.let { params ->
                params.marginEnd = dp(EXIT_BUTTON_GAP_DP / 2)
                continueButton.layoutParams = params
            }
            (exitButton?.layoutParams as? ViewGroup.MarginLayoutParams)?.let { params ->
                params.marginStart = dp(EXIT_BUTTON_GAP_DP / 2)
                exitButton.layoutParams = params
            }
            continueButton?.setOnKeyListener { _, keyCode, event ->
                if (
                    event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_RIGHT ||
                        keyCode == KeyEvent.KEYCODE_DPAD_DOWN)
                ) {
                    exitButton?.requestFocus()
                    true
                } else {
                    false
                }
            }
            exitButton?.setOnKeyListener { _, keyCode, event ->
                if (
                    event.action == KeyEvent.ACTION_DOWN &&
                    (keyCode == KeyEvent.KEYCODE_DPAD_LEFT ||
                        keyCode == KeyEvent.KEYCODE_DPAD_UP)
                ) {
                    continueButton?.requestFocus()
                    true
                } else {
                    false
                }
            }
            dialog.window?.setLayout(
                min(dp(520), resources.displayMetrics.widthPixels - dp(64)),
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            if (hasCustomNativeTheme) {
                dialog.window?.setBackgroundDrawable(
                    roundedThemeDrawable(
                        colorWithAlpha(themeSurfaceColor, 0xFA),
                        16f,
                        dp(1),
                        colorWithAlpha(themePrimaryTextColor, 0x4D),
                    ),
                )
            }
            continueButton?.requestFocus()
        }
        dialog.show()
    }

    private fun requestTransportFocus() {
        val playPause = playerView.findViewById<View>(androidx.media3.ui.R.id.exo_play_pause)
        if (playPause?.requestFocus() != true) playerView.requestFocus()
    }

    private fun armControllerAutoHide() {
        handler.removeCallbacks(hideControllerRunnable)
        if (
            ::playerView.isInitialized &&
            playerView.isControllerFullyVisible &&
            activeTrackDialog?.isShowing != true
        ) {
            handler.postDelayed(hideControllerRunnable, CONTROLLER_HIDE_TIMEOUT_MS)
        }
    }

    // ComponentActivity exposes the platform Activity dispatch hook through
    // androidx.core with a library-group annotation. Overriding it is required
    // here so a hidden controller can consume the first DPAD-left/right event
    // before a video or time bar sees it.
    @SuppressLint("RestrictedApi")
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!::playerView.isInitialized) return super.dispatchKeyEvent(event)
        // Clear a shortcut's paired key-up even when the key-down opened a
        // modal dialog. Otherwise the next same shortcut can be swallowed.
        consumedNavigationKeyUp?.let { consumedKey ->
            if (event.keyCode == consumedKey) {
                if (event.action == KeyEvent.ACTION_UP) consumedNavigationKeyUp = null
                return true
            }
        }
        // Modal dialogs own directional focus. Letting the hidden controller
        // consume their first Left/Right press made "Exit video" unreachable
        // on a number of Fire TV and Google TV remotes.
        if (exitDialog?.isShowing == true || activeTrackDialog?.isShowing == true) {
            return super.dispatchKeyEvent(event)
        }
        if (::skipSegmentButton.isInitialized && skipSegmentButton.hasFocus()) {
            return super.dispatchKeyEvent(event)
        }

        val isInitialKeyDown = event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0
        if (isInitialKeyDown) {
            if (handleChromeShortcut(event.keyCode)) {
                // AlertDialog has its own Window and receives the key-up, so
                // only shortcuts that stay in this Activity arm paired-key
                // suppression. Dialog dismiss also clears any older value.
                if (event.keyCode !in MODAL_CHROME_SHORTCUT_KEYS) {
                    consumedNavigationKeyUp = event.keyCode
                }
                return true
            }
            if (event.keyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
                if (playerView.isControllerFullyVisible) {
                    consumedNavigationKeyUp = event.keyCode
                    handler.removeCallbacks(hideControllerRunnable)
                    playerView.hideController()
                    return true
                }
            }

            if (event.keyCode in CONTROLLER_NAVIGATION_KEYS) {
                if (!playerView.isControllerFullyVisible) {
                    // The first direction press only opens the controls. This
                    // prevents DPAD-left/right from leaking into a seek path.
                    consumedNavigationKeyUp = event.keyCode
                    playerView.showController()
                    requestTransportFocus()
                    armControllerAutoHide()
                    return true
                }
                armControllerAutoHide()
            } else if (event.keyCode in CONTROLLER_INTERACTION_KEYS) {
                // Dedicated media buttons still perform their native action,
                // but the viewer should also see the updated play/seek state.
                if (!playerView.isControllerFullyVisible) {
                    playerView.showController()
                }
                armControllerAutoHide()
            }
        }

        val handled = super.dispatchKeyEvent(event)
        if (
            event.action == KeyEvent.ACTION_UP &&
            playerView.isControllerFullyVisible &&
            event.keyCode in CONTROLLER_INTERACTION_KEYS
        ) {
            armControllerAutoHide()
        }
        return handled
    }

    /** Keyboard/gamepad shortcuts shared with the Flutter MPV and VLC HUDs. */
    private fun handleChromeShortcut(keyCode: Int): Boolean {
        when (keyCode) {
            KeyEvent.KEYCODE_J -> seekRelative(-seekBackIncrementMs, playerView)
            KeyEvent.KEYCODE_L -> seekRelative(seekForwardIncrementMs, playerView)
            KeyEvent.KEYCODE_K -> if (isPlaybackIntended()) player.pause() else player.play()
            KeyEvent.KEYCODE_S -> showTrackPicker(C.TRACK_TYPE_TEXT, captionTrackButton)
            KeyEvent.KEYCODE_C -> showPlayerPicker(fixVideoButton)
            KeyEvent.KEYCODE_A,
            KeyEvent.KEYCODE_BUTTON_X,
            -> cyclePictureMode(pictureModeButton)
            KeyEvent.KEYCODE_I -> {
                val segment = activeSkipSegment ?: return false
                seekPastSkipSegment(segment, announce = false)
            }
            KeyEvent.KEYCODE_M,
            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_BUTTON_Y,
            -> showPlaybackOptions(optionsButton)
            else -> return false
        }
        if (!playerView.isControllerFullyVisible) playerView.showController()
        armControllerAutoHide()
        return true
    }

    private fun applyPreferredAudioOverride(tracks: Tracks) {
        if (preferredAudioOverrideApplied || audioPreferenceChanged || activeTrackDialog != null) {
            return
        }
        val preferredTags = preferredLanguageTags(preferredAudioLanguage).toSet()
        val normalizedPreference = preferredAudioLanguage.trim().lowercase()
        var bestGroup: Tracks.Group? = null
        var bestTrack = -1
        var bestScore = Int.MIN_VALUE
        var bestNonCommentaryGroup: Tracks.Group? = null
        var bestNonCommentaryTrack = -1
        var bestNonCommentaryScore = Int.MIN_VALUE
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_AUDIO) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSupported(index)) continue
                val format = group.getTrackFormat(index)
                val language = format.language.orEmpty().lowercase()
                val label = format.label.orEmpty().lowercase()
                val description = "$language $label"
                val isPreferred = language in preferredTags ||
                    normalizedPreference in description ||
                    (normalizedPreference in setOf("eng", "en", "english") &&
                        ("english" in description || "eng " in description || "dub" in description)) ||
                    (normalizedPreference in setOf("jpn", "ja", "japanese") &&
                        ("japanese" in description || "jpn" in description || "original" in description))
                val isCommentary =
                    "commentary" in description ||
                        "descriptive" in description ||
                        "description" in description
                var score = 0
                if (language in preferredTags) score += 120
                if (normalizedPreference in description) score += 70
                if (
                    normalizedPreference in setOf("eng", "en", "english") &&
                    ("english" in description || "eng " in description || "dub" in description)
                ) score += 100
                if (
                    normalizedPreference in setOf("jpn", "ja", "japanese") &&
                    ("japanese" in description || "jpn" in description || "original" in description)
                ) score += 100
                if (format.selectionFlags and C.SELECTION_FLAG_DEFAULT != 0) score += 10
                score += format.channelCount.coerceIn(0, 8)
                if (isCommentary) score -= 250
                if (score > bestScore) {
                    bestScore = score
                    bestGroup = group
                    bestTrack = index
                }
                if (!isCommentary && score > bestNonCommentaryScore) {
                    bestNonCommentaryScore = score
                    bestNonCommentaryGroup = group
                    bestNonCommentaryTrack = index
                }
            }
        }
        // Never let a preferred-language commentary track outrank normal
        // dialogue. When the requested language is unavailable, explicitly
        // select the best deterministic non-commentary fallback rather than
        // trusting a container default that may itself be commentary.
        val usePreferred = bestGroup != null && bestTrack >= 0 &&
            bestGroup.getTrackFormat(bestTrack).let { format ->
                nativePreferredAudioCandidateIsUsable(
                    bestScore,
                    "${format.language.orEmpty()} ${format.label.orEmpty()}",
                )
            }
        val group = if (usePreferred) bestGroup else bestNonCommentaryGroup ?: bestGroup ?: return
        val track = if (usePreferred) bestTrack else if (bestNonCommentaryGroup != null) {
            bestNonCommentaryTrack
        } else {
            bestTrack
        }
        if (track < 0) return
        val override = TrackSelectionOverride(group.mediaTrackGroup, track)
        val action = nativePreferredAudioOverrideAction(
            preferredAlreadyApplied = preferredAudioOverrideApplied,
            viewerSelectionActive = audioPreferenceChanged || activeTrackDialog != null,
            candidateMatchesPreference = usePreferred,
            candidateMatchesLastOverride = override == lastAutomaticAudioOverride,
        )
        if (action.markPreferredApplied) preferredAudioOverrideApplied = true
        if (!action.applyOverride) return
        lastAutomaticAudioOverride = override
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setOverrideForType(override)
            .build()
    }

    override fun onVideoDecoderInitialized(
        eventTime: AnalyticsListener.EventTime,
        decoderName: String,
        initializedTimestampMs: Long,
        initializationDurationMs: Long,
    ) {
        this.decoderName = decoderName
    }

    override fun onDroppedVideoFrames(
        eventTime: AnalyticsListener.EventTime,
        droppedFrames: Int,
        elapsedMs: Long,
    ) {
        this.droppedFrames += droppedFrames
        if (!firstFrameRendered || !isForeground || !player.isPlaying) return
        dropWindowFrames += droppedFrames
        dropWindowElapsedMs += elapsedMs.coerceAtLeast(0L)
        if (dropWindowElapsedMs < CHOPPY_WINDOW_MIN_MS) return
        val frameRate = (player.videoFormat?.frameRate ?: 0f).takeIf { it > 0f } ?: 24f
        val expectedFrames = frameRate * dropWindowElapsedMs / 1_000f
        val droppedRatio = dropWindowFrames / max(1f, expectedFrames)
        if (dropWindowFrames >= CHOPPY_MIN_DROPPED_FRAMES && droppedRatio >= CHOPPY_DROP_RATIO) {
            consecutiveChoppyWindows++
        } else {
            consecutiveChoppyWindows = 0
        }
        val sampledFrames = dropWindowFrames
        val sampledMs = dropWindowElapsedMs
        resetDropWindow(keepConsecutiveCount = true)
        if (consecutiveChoppyWindows >= CHOPPY_CONSECUTIVE_WINDOWS) {
            terminalError =
                    "Media3 detected excessive dropped frames " +
                    "($sampledFrames in ${sampledMs / 1_000f}s, " +
                    "ratio=${(droppedRatio * 100).toInt()}%, " +
                    "decoder=${decoderName ?: "unknown"})."
            finishWithResult(STATUS_ERROR)
        }
    }

    private fun resetDropWindow(keepConsecutiveCount: Boolean = false) {
        dropWindowElapsedMs = 0L
        dropWindowFrames = 0
        if (!keepConsecutiveCount) consecutiveChoppyWindows = 0
    }

    private fun hasSelectedVideoTrack(): Boolean =
        player.currentTracks.groups.any { group ->
            group.type == C.TRACK_TYPE_VIDEO && group.isSelected
        }

    private fun safePositionMs(): Long =
        if (::player.isInitialized && !playerCoreReleased) {
            runCatching { player.currentPosition.coerceAtLeast(0L) }.getOrDefault(0L)
        } else 0L

    private fun safeDurationMs(): Long {
        if (!::player.isInitialized || playerCoreReleased) return 0L
        return runCatching {
            player.duration.takeIf { it != C.TIME_UNSET && it > 0L } ?: 0L
        }.getOrDefault(0L)
    }

    private fun persistCheckpoint() {
        if (
            checkpointKey.isBlank() ||
            !::player.isInitialized ||
            playerCoreReleased
        ) return
        val duration = safeDurationMs()
        val position = safePositionMs()
        val completed = duration > 0L && position.toDouble() / duration >= 0.93
        checkpointPreferences.edit()
            .putLong(positionKey(), if (completed) 0L else position)
            .putLong(durationKey(), duration)
            .putBoolean(completedKey(), completed)
            .putLong(updatedKey(), System.currentTimeMillis())
            .apply()
    }

    private fun clearNativeCheckpoint() {
        checkpointPreferences.edit()
            .remove(positionKey())
            .remove(durationKey())
            .remove(completedKey())
            .remove(updatedKey())
            .apply()
    }

    private fun positionKey() = "$checkpointKey.positionMs"
    private fun durationKey() = "$checkpointKey.durationMs"
    private fun completedKey() = "$checkpointKey.completed"
    private fun updatedKey() = "$checkpointKey.updatedAt"

    override fun onPause() {
        isForeground = false
        pauseScheduledWork()
        if (::player.isInitialized && !playerCoreReleased && !resultSent) {
            persistCheckpoint()
            resumeAfterTransientPause = runCatching { player.playWhenReady }.getOrDefault(false)
            runCatching { player.pause() }
        }
        super.onPause()
    }

    override fun onStart() {
        super.onStart()
        if (
            backgroundStopped &&
            ::player.isInitialized &&
            !resultSent &&
            !playerCoreReleased
        ) {
            firstFrameRendered = false
            resetDropWindow()
            runCatching {
                player.setMediaItem(buildMediaItem(), backgroundResumeMs.coerceAtLeast(0L))
                player.prepare()
                player.playWhenReady = false
                backgroundStopped = false
            }
        }
    }

    override fun onResume() {
        super.onResume()
        isForeground = true
        enterImmersiveMode()
        if (
            ::player.isInitialized &&
            resumeAfterTransientPause &&
            !resultSent &&
            !playerCoreReleased
        ) {
            resumeAfterTransientPause = false
            runCatching { player.play() }
        }
        armForegroundWork()
    }

    override fun onStop() {
        pauseScheduledWork()
        persistCheckpoint()
        if (::player.isInitialized && !resultSent && !playerCoreReleased) {
            // Release renderers, MediaCodec, network loading, and the large
            // progressive buffer while another app owns the screen. The same
            // ExoPlayer/MediaSession is prepared from this exact position in
            // onStart, avoiding decoder starvation on low-memory TV devices.
            backgroundResumeMs = safePositionMs()
            backgroundStopped = true
            runCatching {
                player.stop()
                player.clearMediaItems()
            }
        }
        super.onStop()
    }

    private fun pauseScheduledWork() {
        handler.removeCallbacks(checkpointRunnable)
        handler.removeCallbacks(skipSegmentRunnable)
        handler.removeCallbacks(skipFetchRetryRunnable)
        handler.removeCallbacks(skipDurationStabilityRunnable)
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
        handler.removeCallbacks(hideControllerRunnable)
        pendingAudioTrackPicker?.let(handler::removeCallbacks)
        pendingAudioTrackPicker = null
    }

    private fun armForegroundWork() {
        pauseScheduledWork()
        if (
            resultSent ||
            playerCoreReleased ||
            !isForeground ||
            !::player.isInitialized
        ) return
        handler.postDelayed(checkpointRunnable, CHECKPOINT_INTERVAL_MS)
        handler.post(skipSegmentRunnable)
        fetchSkipSegmentsIfReady()
        if (playerView.isControllerFullyVisible) armControllerAutoHide()
        if (firstFrameRendered) return
        if (player.playbackState == Player.STATE_READY && hasSelectedVideoTrack()) {
            handler.postDelayed(firstFrameWatchdog, FIRST_FRAME_TIMEOUT_MS)
        } else {
            handler.postDelayed(startupWatchdog, STARTUP_TIMEOUT_MS)
        }
    }

    override fun onDestroy() {
        // Flutter starts the selected replacement engine as soon as it
        // receives the Activity result. Do not let this older Activity's
        // delayed onDestroy clear the replacement engine's fresh presence.
        if (!preserveDiscordPresenceForEngineHandoff) {
            DiscordRichPresenceBridge.clearPlayback()
        }
        exitDialog?.dismiss()
        exitDialog = null
        activeTrackDialog?.dismiss()
        activeTrackDialog = null
        val metadataDispatcher = metadataClient.dispatcher
        val metadataConnectionPool = metadataClient.connectionPool
        Media3NetworkCleanup.shared.schedule(
            cancelCalls = metadataDispatcher::cancelAll,
            evictConnections = metadataConnectionPool::evictAll,
        )
        handler.removeCallbacksAndMessages(null)
        releasePlaybackResources()
        super.onDestroy()
    }

    private fun releasePlaybackResources() {
        if (playbackResourcesReleased) return
        if (!playerViewReleased) {
            playerViewReleased = !::playerView.isInitialized || runCatching {
                (playerView.videoSurfaceView as? SurfaceView)?.holder
                    ?.removeCallback(surfaceCallback)
                playerView.player = null
            }.isSuccess
        }
        if (!playerListenersReleased) {
            playerListenersReleased = !::player.isInitialized || runCatching {
                player.removeListener(this)
                player.removeAnalyticsListener(this)
            }.isSuccess
        }
        if (!mediaSessionReleased) {
            mediaSessionReleased = !::mediaSession.isInitialized ||
                runCatching { mediaSession.release() }.isSuccess
        }
        if (!playerCoreReleased) {
            playerCoreReleased = !::player.isInitialized ||
                runCatching { player.release() }.isSuccess
        }
        playbackResourcesReleased = playerViewReleased &&
            playerListenersReleased &&
            mediaSessionReleased &&
            playerCoreReleased
    }

    private fun finishWithResult(status: String) {
        if (resultSent) return
        resultSent = true
        handler.removeCallbacks(firstFrameWatchdog)
        handler.removeCallbacks(startupWatchdog)
        handler.removeCallbacks(checkpointRunnable)
        handler.removeCallbacks(skipSegmentRunnable)
        handler.removeCallbacks(skipFetchRetryRunnable)
        handler.removeCallbacks(hideControllerRunnable)
        persistCheckpoint()
        val duration = safeDurationMs()
        val position = safePositionMs()
        val completed = status == STATUS_COMPLETED ||
            (duration > 0L && position.toDouble() / duration >= 0.93)
        val result = Intent().apply {
            putExtra(RESULT_POSITION_MS, position)
            putExtra(RESULT_DURATION_MS, duration)
            putExtra(RESULT_COMPLETED, completed)
            putExtra(RESULT_ERROR, terminalError)
            putExtra(RESULT_FIRST_FRAME, everFirstFrameRendered)
            putExtra(RESULT_DECODER, decoderName)
            putExtra(RESULT_DROPPED_FRAMES, droppedFrames)
            putExtra(RESULT_SUBTITLE_SIZE, subtitleSize)
            putExtra(RESULT_SUBTITLE_BACKGROUND_COLOR, subtitleBackgroundColor)
            putExtra(RESULT_HIGH_CONTRAST_SUBTITLES, highContrastSubtitles)
            putExtra(RESULT_AUDIO_LANGUAGE, selectedTrackLanguage(C.TRACK_TYPE_AUDIO))
            putExtra(RESULT_AUDIO_PREFERENCE_SET, audioPreferenceChanged)
            putExtra(RESULT_SUBTITLE_LANGUAGE, selectedTrackLanguage(C.TRACK_TYPE_TEXT))
            putExtra(RESULT_SUBTITLES_ENABLED, hasSelectedTextTrack())
            putExtra(RESULT_SURFACE_READY, surfaceReady)
            putExtra(RESULT_MANUFACTURER, Build.MANUFACTURER)
            putExtra(RESULT_MODEL, Build.MODEL)
            putExtra(RESULT_SDK, Build.VERSION.SDK_INT)
            putExtra(RESULT_ABIS, Build.SUPPORTED_ABIS)
            putExtra(RESULT_MEMORY_CLASS_MB, memoryClassMb())
            putExtra(RESULT_LOW_MEMORY_DEVICE, isLowMemoryDevice())
            putExtra(RESULT_VIDEO_MIME, playerVideoFormat()?.sampleMimeType)
            putExtra(RESULT_VIDEO_CODECS, playerVideoFormat()?.codecs)
            putExtra(RESULT_VIDEO_WIDTH, playerVideoFormat()?.width ?: 0)
            putExtra(RESULT_VIDEO_HEIGHT, playerVideoFormat()?.height ?: 0)
            putExtra(RESULT_VIDEO_FRAME_RATE, playerVideoFormat()?.frameRate ?: 0f)
            putExtra(RESULT_AUDIO_MIME, playerAudioFormat()?.sampleMimeType)
            putExtra(RESULT_AUDIO_CODECS, playerAudioFormat()?.codecs)
        }
        // The caller may construct MPV or VLC as soon as this Activity result
        // is delivered. Release MediaCodec, SurfaceView, audio, and MediaSession
        // synchronously before setResult()/finish() can resume Flutter.
        releasePlaybackResources()
        val switchingEngine =
            status == STATUS_USE_MPV || status == STATUS_USE_VLC || status == STATUS_NEXT_STREAM
        val deliveredStatus = if (switchingEngine && !playbackResourcesReleased) {
            terminalError =
                "Media3 could not release every playback resource safely. " +
                "Return to the episode and try again."
            result.putExtra(RESULT_ERROR, terminalError)
            STATUS_RELEASE_FAILED
        } else {
            status
        }
        result.putExtra(RESULT_STATUS, deliveredStatus)
        preserveDiscordPresenceForEngineHandoff =
            deliveredStatus == STATUS_USE_MPV ||
                deliveredStatus == STATUS_USE_VLC ||
                deliveredStatus == STATUS_NEXT_STREAM
        setResult(RESULT_OK, result)
        // Normal Exit must remain reachable even if a device-specific cleanup
        // step failed. Engine switches are withheld above until every old
        // Surface/codec/session owner has released its resources.
        finish()
    }

    private fun memoryClassMb(): Int =
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).memoryClass

    private fun isLowMemoryDevice(): Boolean =
        (getSystemService(ACTIVITY_SERVICE) as ActivityManager).isLowRamDevice

    private fun playerVideoFormat() =
        if (::player.isInitialized) player.videoFormat else null

    private fun playerAudioFormat() =
        if (::player.isInitialized) player.audioFormat else null

    private fun hasSelectedTextTrack(): Boolean =
        ::player.isInitialized && player.currentTracks.groups.any {
            it.type == C.TRACK_TYPE_TEXT && it.isSelected
        }

    private fun selectedTrackLanguage(trackType: Int): String? {
        if (!::player.isInitialized) return null
        for (group in player.currentTracks.groups) {
            if (group.type != trackType || !group.isSelected) continue
            for (index in 0 until group.length) {
                if (!group.isTrackSelected(index)) continue
                val format = group.getTrackFormat(index)
                return nativeSelectedTrackLanguage(format.language, format.label)
            }
        }
        return null
    }

    @Suppress("DEPRECATION")
    private fun enterImmersiveMode() {
        window.decorView.systemUiVisibility =
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
    }

    companion object {
        const val EXTRA_SOURCE = "source"
        const val EXTRA_TITLE = "title"
        const val EXTRA_ARTWORK_URL = "artworkUrl"
        const val EXTRA_STREAM_LABEL = "streamLabel"
        const val EXTRA_SUBTITLE_URL = "subtitleUrl"
        const val EXTRA_SUBTITLE_MIME_TYPE = "subtitleMimeType"
        const val EXTRA_SUBTITLE_LANGUAGE = "subtitleLanguage"
        const val EXTRA_SUBTITLE_LABEL = "subtitleLabel"
        const val EXTRA_SUBTITLE_REJECTED = "externalSubtitleRejected"
        const val EXTRA_MIME_TYPE = "mimeType"
        const val EXTRA_FILE_NAME = "fileName"
        const val EXTRA_HEADERS = "headers"
        const val EXTRA_RESUME_MS = "resumeMs"
        const val EXTRA_RESUME_PROVIDED = "resumeProvided"
        const val EXTRA_RESUME_UPDATED_AT_MS = "resumeUpdatedAtMs"
        const val EXTRA_AUTO_PLAY = "autoPlay"
        const val EXTRA_AUDIO_LANGUAGE = "audioLanguage"
        const val EXTRA_SUBTITLES_ENABLED = "subtitlesEnabled"
        const val EXTRA_SUBTITLE_SIZE = "subtitleSize"
        const val EXTRA_SUBTITLE_POSITION = "subtitlePosition"
        const val EXTRA_HIGH_CONTRAST_SUBTITLES = "highContrastSubtitles"
        const val EXTRA_SUBTITLE_TEXT_COLOR = "subtitleTextColor"
        const val EXTRA_SUBTITLE_BACKGROUND_COLOR = "subtitleBackgroundColor"
        const val EXTRA_SEEK_BACK_MS = "seekBackMs"
        const val EXTRA_SEEK_FORWARD_MS = "seekForwardMs"
        const val EXTRA_AUTO_SKIP_INTROS = "autoSkipIntros"
        const val EXTRA_AUTO_SKIP_OUTROS = "autoSkipOutros"
        const val EXTRA_VIDEO_FIT = "videoFit"
        const val EXTRA_START_FROM_BEGINNING = "startFromBeginning"
        const val EXTRA_CHECKPOINT_KEY = "checkpointKey"
        const val EXTRA_MAL_MEDIA_ID = "malMediaId"
        const val EXTRA_EPISODE_NUMBER = "episodeNumber"
        const val EXTRA_HAS_DIRECT_SOURCES = "hasDirectSources"
        const val EXTRA_TRUSTED_LOCAL_SOURCE = "trustedLocalSource"
        const val EXTRA_TRUSTED_PLAYBACK_PROXY = "trustedPlaybackProxy"
        const val EXTRA_THEME_BACKGROUND_COLOR = "themeBackgroundColor"
        const val EXTRA_THEME_SURFACE_COLOR = "themeSurfaceColor"
        const val EXTRA_THEME_ACCENT_COLOR = "themeAccentColor"
        const val EXTRA_THEME_ACCENT_BRIGHT_COLOR = "themeAccentBrightColor"
        const val EXTRA_THEME_FOCUS_COLOR = "themeFocusColor"
        const val EXTRA_THEME_PRIMARY_TEXT_COLOR = "themePrimaryTextColor"
        const val EXTRA_THEME_MUTED_TEXT_COLOR = "themeMutedTextColor"

        const val RESULT_STATUS = "status"
        const val RESULT_POSITION_MS = "positionMs"
        const val RESULT_DURATION_MS = "durationMs"
        const val RESULT_COMPLETED = "completed"
        const val RESULT_ERROR = "error"
        const val RESULT_FIRST_FRAME = "firstFrame"
        const val RESULT_DECODER = "decoder"
        const val RESULT_DROPPED_FRAMES = "droppedFrames"
        const val RESULT_SUBTITLE_SIZE = "subtitleSize"
        const val RESULT_SUBTITLE_BACKGROUND_COLOR = "subtitleBackgroundColor"
        const val RESULT_HIGH_CONTRAST_SUBTITLES = "highContrastSubtitles"
        const val RESULT_AUDIO_LANGUAGE = "audioLanguage"
        const val RESULT_AUDIO_PREFERENCE_SET = "audioPreferenceSet"
        const val RESULT_SUBTITLE_LANGUAGE = "subtitleLanguage"
        const val RESULT_SUBTITLES_ENABLED = "subtitlesEnabled"
        const val RESULT_SURFACE_READY = "surfaceReady"
        const val RESULT_MANUFACTURER = "manufacturer"
        const val RESULT_MODEL = "model"
        const val RESULT_SDK = "sdk"
        const val RESULT_ABIS = "abis"
        const val RESULT_MEMORY_CLASS_MB = "memoryClassMb"
        const val RESULT_LOW_MEMORY_DEVICE = "lowMemoryDevice"
        const val RESULT_VIDEO_MIME = "videoMime"
        const val RESULT_VIDEO_CODECS = "videoCodecs"
        const val RESULT_VIDEO_WIDTH = "videoWidth"
        const val RESULT_VIDEO_HEIGHT = "videoHeight"
        const val RESULT_VIDEO_FRAME_RATE = "videoFrameRate"
        const val RESULT_AUDIO_MIME = "audioMime"
        const val RESULT_AUDIO_CODECS = "audioCodecs"

        const val STATUS_COMPLETED = "completed"
        const val STATUS_STOPPED = "stopped"
        const val STATUS_ERROR = "error"
        const val STATUS_USE_MPV = "use_mpv"
        const val STATUS_USE_VLC = "use_vlc"
        const val STATUS_NEXT_STREAM = "next_stream"
        const val STATUS_RELEASE_FAILED = "release_failed"

        private const val SKIP_DURATION_STABILITY_DELAY_MS = 1_200L
        private const val SKIP_DURATION_STABILITY_TOLERANCE_MS = 1_000L
        private const val FOCUS_REVEAL_INSET_DP = 8
        private const val CHROME_FOCUS_SCALE = 1.025f
        private const val CHROME_FOCUS_ANIMATION_MS = 80L
        private const val HUD_ACTION_LABEL_SIZE_DP = 11f
        private const val HUD_SKIP_LABEL_SIZE_DP = 14f
        private const val HUD_MAX_TEXT_SCALE = 1.35f
        private val CHROME_FOCUS_INTERPOLATOR = PathInterpolator(0.215f, 0.61f, 0.355f, 1f)

        // Theme Studio's default seeds are translated back to the exact native
        // HUD colors that shipped before customization support.
        private val FLUTTER_DEFAULT_BACKGROUND = 0xFF030303.toInt()
        private val FLUTTER_DEFAULT_SURFACE = 0xFF101010.toInt()
        private val FLUTTER_DEFAULT_PRIMARY_TEXT = 0xFFF8F5F6.toInt()
        private val LEGACY_THEME_SURFACE = 0xFF080808.toInt()
        private val LEGACY_THEME_ACCENT = 0xFFE52B50.toInt()
        private val LEGACY_THEME_ACCENT_BRIGHT = 0xFFFF496A.toInt()
        private val LEGACY_THEME_FOCUS = 0xFFFF5C78.toInt()
        private val LEGACY_THEME_MUTED_TEXT = 0xFFB7AEB1.toInt()

        private const val CHECKPOINT_PREFERENCES = "native_media3_checkpoints"
        private const val CHECKPOINT_INTERVAL_MS = 5_000L
        private const val CONTROLLER_HIDE_TIMEOUT_MS = 5_000L
        private const val AUDIO_TRACK_POLL_MS = 250L
        private const val AUDIO_TRACK_DEFAULT_WAIT_MS = 2_000L
        private const val AUDIO_TRACK_ADVERTISED_WAIT_MS = 5_000L
        private const val SKIP_SEGMENT_POLL_MS = 300L
        private const val MAX_SKIP_FETCH_ATTEMPTS = 3
        private const val MAX_SKIP_RESPONSE_BYTES = 256L * 1024L
        private const val SKIP_FETCH_RETRY_BASE_MS = 2_000L
        private const val MIN_SKIP_SEGMENT_MS = 8_000L
        private const val MAX_SKIP_SEGMENT_MS = 240_000L
        private const val DEFAULT_SUBTITLE_SIZE = 34f
        private val CAPTION_DARK_BACKGROUND = 0x99000000.toInt()
        private val CAPTION_HIGH_CONTRAST_BACKGROUND = 0xDD000000.toInt()
        private const val EXIT_BUTTON_GAP_DP = 12
        private val SUBTITLE_SIZE_VALUES = floatArrayOf(28f, 34f, 42f, 50f)
        private const val DISABLED_CONTROL_ALPHA = 0.38f
        private const val FIRST_FRAME_TIMEOUT_MS = 12_000L
        private const val STARTUP_TIMEOUT_MS = 45_000L
        private const val CHOPPY_WINDOW_MIN_MS = 4_000L
        private const val CHOPPY_MIN_DROPPED_FRAMES = 20
        private const val CHOPPY_DROP_RATIO = 0.25f
        private const val CHOPPY_CONSECUTIVE_WINDOWS = 2
        private val CONTROLLER_NAVIGATION_KEYS = setOf(
            KeyEvent.KEYCODE_DPAD_UP,
            KeyEvent.KEYCODE_DPAD_DOWN,
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_CENTER,
            KeyEvent.KEYCODE_ENTER,
        )
        private val SKIP_TO_CONTROLLER_KEYS = setOf(
            KeyEvent.KEYCODE_DPAD_LEFT,
            KeyEvent.KEYCODE_DPAD_RIGHT,
            KeyEvent.KEYCODE_DPAD_DOWN,
        )
        private val CONTROLLER_INTERACTION_KEYS = CONTROLLER_NAVIGATION_KEYS + setOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_PLAY,
            KeyEvent.KEYCODE_MEDIA_PAUSE,
            KeyEvent.KEYCODE_MEDIA_REWIND,
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD,
        )
        private val MODAL_CHROME_SHORTCUT_KEYS = setOf(
            KeyEvent.KEYCODE_S,
            KeyEvent.KEYCODE_C,
            KeyEvent.KEYCODE_M,
            KeyEvent.KEYCODE_MENU,
            KeyEvent.KEYCODE_BUTTON_Y,
        )
        private const val SMOKE_VIDEO_REQUEST_URI = "asset:///assets/videos/vlc_smoke.mp4"
        private const val SMOKE_VIDEO_URI =
            "asset:///flutter_assets/assets/videos/vlc_smoke.mp4"
        private const val SMOKE_SUBTITLE_REQUEST_URI =
            "asset:///assets/subtitles/libass_smoke.ass"
        private const val SMOKE_SUBTITLE_URI =
            "asset:///flutter_assets/assets/subtitles/libass_smoke.ass"

        private fun normalizeMediaUri(value: String): String = when (value) {
            SMOKE_VIDEO_REQUEST_URI -> SMOKE_VIDEO_URI
            SMOKE_SUBTITLE_REQUEST_URI -> SMOKE_SUBTITLE_URI
            else -> value
        }

        private fun preferredLanguageTags(language: String): List<String> {
            val normalized = language.trim().lowercase()
            return when (normalized) {
                "eng", "en", "english" -> listOf("en", "eng")
                "jpn", "ja", "japanese" -> listOf("ja", "jpn")
                else -> listOf(normalized)
            }
        }

        private fun preferredAudioLabels(language: String): List<String> {
            val normalized = language.trim().lowercase()
            return when (normalized) {
                "eng", "en", "english" ->
                    listOf("English", "English Dub", "Dub")
                "jpn", "ja", "japanese" ->
                    listOf("Japanese", "Original", "Japan")
                else -> listOf(language.trim()).filter(String::isNotBlank)
            }
        }

        private fun inferContainerMimeType(
            explicit: String?,
            fileName: String?,
            source: String,
        ): String? {
            if (!explicit.isNullOrBlank()) return explicit
            val value = "${fileName.orEmpty()} $source".lowercase().substringBefore('?')
            return when {
                value.contains(".mkv") -> MimeTypes.APPLICATION_MATROSKA
                value.contains(".webm") -> MimeTypes.VIDEO_WEBM
                value.contains(".mp4") || value.contains(".m4v") -> MimeTypes.VIDEO_MP4
                value.contains(".ts") || value.contains(".m2ts") -> MimeTypes.VIDEO_MP2T
                else -> null
            }
        }

        private fun inferSubtitleMimeType(explicit: String?, url: String): String {
            if (!explicit.isNullOrBlank()) return explicit
            return when (url.lowercase().substringBefore('?').substringAfterLast('.')) {
                "ass", "ssa" -> MimeTypes.TEXT_SSA
                "vtt" -> MimeTypes.TEXT_VTT
                "ttml", "xml" -> MimeTypes.APPLICATION_TTML
                else -> MimeTypes.APPLICATION_SUBRIP
            }
        }
    }
}
