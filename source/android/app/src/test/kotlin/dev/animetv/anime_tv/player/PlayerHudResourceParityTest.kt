package dev.animetv.anime_tv.player

import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PlayerHudResourceParityTest {
    @Test
    fun transportActionsAreIconOnlyButRemainAccessible() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val activity = activitySource()
        val controls = listOf(
            "tetotv_rewind_control" to "@string/tetotv_player_rewind",
            "tetotv_play_pause_control" to "@string/tetotv_player_play",
            "tetotv_fast_forward_control" to "@string/tetotv_player_fast_forward",
        )

        controls.forEach { (controlId, accessibilityLabel) ->
            val control = layout.substringAfter("android:id=\"@+id/$controlId\"")
                .substringBefore("</LinearLayout>")
            assertTrue(control.contains("android:layout_width=\"40dp\""))
            assertTrue(control.contains("android:contentDescription=\"$accessibilityLabel\""))
            assertFalse(control.contains("<TextView"))
        }
        listOf(
            "tetotv_rewind_label",
            "tetotv_play_pause_label",
            "tetotv_fast_forward_label",
        ).forEach { assertFalse(layout.contains(it)) }
        assertTrue(activity.contains("playPauseButton.contentDescription = getString("))
        assertTrue(activity.contains("R.string.tetotv_player_pause"))
        assertTrue(activity.contains("R.string.tetotv_player_play"))
        assertTrue(activity.contains("R.string.tetotv_player_rewind_seconds"))
        assertTrue(activity.contains("R.string.tetotv_player_fast_forward_seconds"))
    }

    @Test
    fun media3MatchesMpvChromeGeometryPaletteAndReadOnlyProgress() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val playerLayout = resource("layout/activity_media3_player.xml").readText()
        val styles = resource("values/styles.xml").readText()
        val nightStyles = resource("values-night/styles.xml").readText()
        val card = resource("drawable/tetotv_player_card_background.xml").readText()
        val badge = resource("drawable/tetotv_player_badge_background.xml").readText()
        val normalControl =
            resource("drawable/tetotv_player_control_pill_background.xml").readText()
        val primaryControl =
            resource("drawable/tetotv_player_control_primary_background.xml").readText()
        val scrim = resource("drawable/tetotv_player_controls_scrim.xml").readText()
        val compactDimensions = resource("values/player_hud_dimensions.xml").readText()
        val regularDimensions = source(
            "main/res/values-w720dp-h480dp/player_hud_dimensions.xml",
        ).readText()

        listOf(
            "android:layout_marginStart=\"28dp\"",
            "android:layout_marginBottom=\"24dp\"",
            "android:paddingStart=\"18dp\"",
            "android:paddingTop=\"14dp\"",
            "android:paddingBottom=\"12dp\"",
            "android:textSize=\"24sp\"",
            "app:bar_height=\"@dimen/tetotv_player_progress_bar_height\"",
            "app:played_color=\"#FFFF496A\"",
            "app:unplayed_color=\"#3DFFFFFF\"",
            "android:textColor=\"#FFB7AEB1\"",
        ).forEach { assertTrue(layout.contains(it)) }
        listOf(styles, nightStyles).forEach { styleSource ->
            assertTrue(styleSource.contains("<item name=\"android:layout_height\">40dp</item>"))
            assertTrue(styleSource.contains("<item name=\"android:ellipsize\">end</item>"))
            assertTrue(styleSource.contains("<item name=\"android:maxLines\">1</item>"))
            assertTrue(
                Regex(
                    """<style name="TetoTVPlayerBadge"[\s\S]*?""" +
                        """<item name="android:layout_height">wrap_content</item>""",
                ).containsMatchIn(styleSource),
            )
            assertTrue(styleSource.contains("<item name=\"android:textColor\">#FFFF496A</item>"))
            assertFalse(styleSource.contains("<item name=\"android:layout_height\">44dp</item>"))
        }
        listOf("#D6080808", "16dp", "1.4dp", "#C7E52B50")
            .forEach { assertTrue(card.contains(it)) }
        listOf("#33E52B50", "#59E52B50").forEach { assertTrue(badge.contains(it)) }
        assertTrue(normalControl.contains("#8F242429"))
        assertFalse(normalControl.contains("#FF3A3A40"))
        assertTrue(primaryControl.contains("#FFE52B50"))
        assertTrue(scrim.contains("#00000000"))
        assertFalse(scrim.contains("<gradient"))

        val timeBar = layout.substringAfter("<androidx.media3.ui.DefaultTimeBar")
            .substringBefore("/>")
        listOf(
            "android:clickable=\"false\"",
            "android:focusable=\"false\"",
            "android:importantForAccessibility=\"no\"",
            "android:longClickable=\"false\"",
            "app:scrubber_disabled_size=\"0dp\"",
            "app:scrubber_dragged_size=\"0dp\"",
            "app:scrubber_enabled_size=\"0dp\"",
        ).forEach { assertTrue(timeBar.contains(it)) }
        assertTrue(playerLayout.contains("app:time_bar_scrubbing_enabled=\"false\""))
        listOf(">3dp<", ">1dp<", ">-9dp<")
            .forEach { assertTrue(compactDimensions.contains(it)) }
        listOf(">4dp<", ">-5dp<")
            .forEach { assertTrue(regularDimensions.contains(it)) }
        listOf(
            "setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)",
            "cornerRadius = dp(12).toFloat()",
            "setTopMargin(dp(7))",
            "setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)",
            "tvSafeHudTextSizePx(HUD_ACTION_LABEL_SIZE_DP)",
            "setTextSize(TypedValue.COMPLEX_UNIT_PX, textSizePx)",
            "ellipsize = TextUtils.TruncateAt.END",
            "private const val HUD_ACTION_LABEL_SIZE_DP = 11f",
            "private const val HUD_MAX_TEXT_SCALE = 1.35f",
            "fontScale.coerceAtMost(HUD_MAX_TEXT_SCALE)",
        ).forEach { assertTrue(activitySource().contains(it)) }
        assertFalse(
            activitySource().contains(
                "findViewById<TextView>(R.id.tetotv_paused_title)\n" +
                    "                .setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)",
            ),
        )
    }

    @Test
    fun media3UsesOwnedIconsAndTetoFocusRing() {
        val layout = resource("layout/tetotv_player_controls.xml").readText()
        val activity = source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
        assertFalse(layout.contains("@android:drawable/ic_menu_"))
        val nativeHudSource = "$layout\n$activity"
        listOf(
            "replay_rounded",
            "play_arrow_rounded",
            "pause_rounded",
            "forward_rounded",
            "picture",
            "player",
            "sources",
            "options",
        ).forEach { name ->
            assertTrue(nativeHudSource.contains("tetotv_ic_$name"))
            val vector = resource("drawable/tetotv_ic_$name.xml").readText()
            assertTrue(vector.contains("<vector"))
            assertTrue(vector.contains("glyph used by Flutter"))
        }

        listOf(
            "tetotv_player_control_pill_background.xml",
            "tetotv_player_control_primary_background.xml",
        ).forEach { name ->
            val selector = resource("drawable/$name").readText()
            assertTrue(selector.contains("android:state_activated=\"true\""))
            assertTrue(selector.contains("android:width=\"3dp\""))
            assertTrue(selector.contains("android:color=\"#FFFF5C78\""))
            assertTrue(selector.contains("android:color=\"#E6000000\""))
            assertFalse(selector.contains("android:color=\"#FFFFFFFF\""))
        }
        assertTrue(activity.contains("control.setOnFocusChangeListener"))
        assertTrue(activity.contains("setChromeControlHighlighted(container, hasFocus)"))
        assertTrue(activity.contains("CHROME_FOCUS_SCALE = 1.025f"))
        assertTrue(activity.contains("CHROME_FOCUS_ANIMATION_MS = 80L"))
        assertTrue(activity.contains("PathInterpolator(0.215f, 0.61f, 0.355f, 1f)"))
        assertTrue(activity.contains("container.requestRectangleOnScreen"))
        assertTrue(layout.contains("android:clipChildren=\"false\""))
        assertTrue(layout.contains("@+id/tetotv_sources_control"))
        assertTrue(activity.contains("STATUS_NEXT_STREAM"))
    }

    @Test
    fun media3ExitAndSkipControlsMatchTheMpvInteractionStyle() {
        val playerLayout = resource("layout/activity_media3_player.xml").readText()
        val skip = resource("drawable/tetotv_skip_button_background.xml").readText()
        val exitBackground =
            resource("drawable/tetotv_player_exit_dialog_background.xml").readText()
        val styles = resource("values/styles.xml").readText()
        val activity = activitySource()

        listOf(
            "android:layout_height=\"wrap_content\"",
            "android:minHeight=\"44dp\"",
            "android:drawableStart=\"@drawable/tetotv_ic_skip_next\"",
            "android:drawablePadding=\"8dp\"",
            "android:paddingStart=\"18dp\"",
            "android:paddingTop=\"11dp\"",
            "android:maxLines=\"1\"",
            "android:ellipsize=\"end\"",
            "android:textSize=\"14sp\"",
        ).forEach { assertTrue(playerLayout.contains(it)) }
        listOf("#B30B0B0D", "#D1FF496A", "#FFFF5C78", "3dp")
            .forEach { assertTrue(skip.contains(it)) }
        listOf("#FA09090B", "16dp", "#4DFFFFFF")
            .forEach { assertTrue(exitBackground.contains(it)) }
        assertTrue(styles.contains("<style name=\"NativePlayerExitDialogTheme\""))
        assertTrue(activity.contains("R.style.NativePlayerExitDialogTheme"))
        assertTrue(activity.contains("min(dp(520), resources.displayMetrics.widthPixels - dp(64))"))
        assertTrue(activity.contains("R.drawable.tetotv_ic_play"))
        assertTrue(activity.contains("R.drawable.tetotv_ic_exit"))
        assertTrue(activity.contains("params.marginEnd = dp(EXIT_BUTTON_GAP_DP / 2)"))
        assertTrue(activity.contains("params.marginStart = dp(EXIT_BUTTON_GAP_DP / 2)"))
        assertTrue(playerLayout.contains("android:nextFocusDown=\"@id/exo_play_pause\""))
        assertTrue(activity.contains("keyCode in SKIP_TO_CONTROLLER_KEYS"))
        assertTrue(activity.contains("!playerView.isControllerFullyVisible"))
        assertTrue(activity.contains("tvSafeHudTextSizePx(HUD_SKIP_LABEL_SIZE_DP)"))
    }

    @Test
    fun media3ExposesCaptionBackgroundCustomizationAndReturnsItsState() {
        val activity = activitySource()
        val strings = resource("values/strings.xml").readText()

        listOf(
            "showSubtitleBackgroundPicker(sourceButton)",
            "CAPTION_DARK_BACKGROUND",
            "CAPTION_HIGH_CONTRAST_BACKGROUND",
            "setStyle(CaptionStyleCompat.DEFAULT)",
            "putExtra(RESULT_SUBTITLE_BACKGROUND_COLOR, subtitleBackgroundColor)",
            "putExtra(RESULT_HIGH_CONTRAST_SUBTITLES, highContrastSubtitles)",
        ).forEach { assertTrue(activity.contains(it)) }
        assertTrue(strings.contains("Caption background"))
    }

    @Test
    fun media3AppliesThemeStudioPayloadAcrossNativeChrome() {
        val activity = activitySource()
        listOf(
            "themeBackgroundColor",
            "themeSurfaceColor",
            "themeAccentColor",
            "themeAccentBrightColor",
            "themeFocusColor",
            "themePrimaryTextColor",
            "themeMutedTextColor",
        ).forEach { key -> assertTrue(activity.contains("\"$key\"")) }
        listOf(
            "readNativePlayerTheme()",
            "applyNativePlayerTheme()",
            "if (!hasCustomNativeTheme) return",
            "playerView.setShutterBackgroundColor(themeBackgroundColor)",
            "themedControlBackground(primary = false)",
            "themedControlBackground(primary = true)",
            "applyThemeForeground(themePrimaryTextColor)",
            "nativeThemeAccentForeground(",
            "R.id.tetotv_play_pause_control",
            "setPlayedColor(themeAccentBrightColor)",
            "setUnplayedColor(colorWithAlpha(themePrimaryTextColor, 0x3D))",
            "themedSkipBackground()",
            "themedDialogButtonBackground(danger = false)",
            "themedDialogButtonBackground(danger = true)",
            "roundedThemeDrawable(",
        ).forEach { assertion -> assertTrue(activity.contains(assertion)) }

        val exitDialog = activity.substringAfter("private fun showExitConfirmation()")
            .substringBefore("private fun requestTransportFocus()")
        assertTrue(exitDialog.contains("val dangerForeground = nativeThemeAccentForeground("))
        assertTrue(exitDialog.contains("setTextColor(dangerForeground)"))
        assertTrue(exitDialog.contains("setTint(dangerForeground)"))

        // Supplying the standard Theme Studio palette must keep the original
        // native black/card/text values and leave XML selectors untouched.
        listOf(
            "FLUTTER_DEFAULT_BACKGROUND",
            "FLUTTER_DEFAULT_SURFACE",
            "FLUTTER_DEFAULT_PRIMARY_TEXT",
            "LEGACY_THEME_SURFACE",
            "LEGACY_THEME_ACCENT",
            "LEGACY_THEME_ACCENT_BRIGHT",
            "LEGACY_THEME_FOCUS",
            "LEGACY_THEME_MUTED_TEXT",
            "return if (supplied == flutterDefault) legacyDefault else supplied",
        ).forEach { assertion -> assertTrue(activity.contains(assertion)) }
    }

    @Test
    fun manualAudioPreferenceIsRecordedOnlyWhenTheSelectedLanguageChanges() {
        val activity = activitySource()
        val trackPicker = activity.substringAfter("private fun showTrackPickerNow")
            .substringBefore("private fun showSubtitleSizePicker")
        val captionBackground = activity.substringAfter("private fun showSubtitleBackgroundPicker")
            .substringBefore("private fun cyclePictureMode")

        assertTrue(
            trackPicker.contains(
                "val audioSelectionParametersBefore = if (trackType == C.TRACK_TYPE_AUDIO)",
            ),
        )
        assertTrue(
            trackPicker.contains(
                "player.trackSelectionParameters != audioSelectionParametersBefore",
            ),
        )
        assertTrue(trackPicker.contains("audioPreferenceChanged = true"))
        assertFalse(captionBackground.contains("audioPreferenceChanged = true"))
    }

    @Test
    fun confirmedExitKeepsTheStoppedReturnContractForFlutterRouting() {
        val activity = activitySource()
        val exit = activity.substringAfter("private fun showExitConfirmation()")
            .substringBefore("private fun requestTransportFocus()")

        assertTrue(exit.contains("finishWithResult(STATUS_STOPPED)"))
        assertTrue(activity.contains("const val STATUS_STOPPED = \"stopped\""))
        assertFalse(exit.contains("finishWithResult(STATUS_COMPLETED)"))
    }

    @Test
    fun shortcutsCleanUpBeforeDialogsAndUsePlaybackIntent() {
        val activity = source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
        val dispatch = activity.substringAfter("override fun dispatchKeyEvent")
            .substringBefore("/** Keyboard/gamepad shortcuts")
        val cleanup = dispatch.indexOf("consumedNavigationKeyUp?.let")
        val modalGuard = dispatch.indexOf("exitDialog?.isShowing == true")
        assertTrue(cleanup >= 0)
        assertTrue(cleanup < modalGuard)
        assertTrue(dispatch.contains("if (event.keyCode !in MODAL_CHROME_SHORTCUT_KEYS)"))
        listOf("KEYCODE_S", "KEYCODE_C", "KEYCODE_M", "KEYCODE_MENU", "KEYCODE_BUTTON_Y")
            .forEach { assertTrue(activity.contains(it)) }
        assertTrue(activity.contains("consumedNavigationKeyUp = null"))
        assertTrue(
            activity.contains(
                "player.playWhenReady && player.playbackState != Player.STATE_ENDED",
            ),
        )
        assertTrue(
            activity.contains(
                "KeyEvent.KEYCODE_K -> if (isPlaybackIntended()) player.pause() else player.play()",
            ),
        )
        assertTrue(activity.contains("playing = isPlaybackIntended()"))
        listOf("KEYCODE_I", "KEYCODE_A", "KEYCODE_BUTTON_X")
            .forEach { assertTrue(activity.contains(it)) }
        assertTrue(activity.contains("controllerAutoShow = false"))
        assertFalse(activity.contains("controllerAutoShow = !isTelevisionDevice()"))
    }

    private fun resource(path: String): File {
        val relative = "src/main/res/$path"
        return listOf(File(relative), File("app/$relative"), File("android/app/$relative"))
            .firstOrNull(File::isFile)
            ?: error("Could not locate Android resource $relative from ${File(".").absolutePath}")
    }

    private fun source(path: String): File {
        val relative = "src/$path"
        return listOf(File(relative), File("app/$relative"), File("android/app/$relative"))
            .firstOrNull(File::isFile)
            ?: error("Could not locate Android source $relative from ${File(".").absolutePath}")
    }

    private fun activitySource(): String =
        source("main/kotlin/dev/animetv/anime_tv/player/Media3PlayerActivity.kt").readText()
}
