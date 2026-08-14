package dev.animetv.anime_tv

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import org.json.JSONObject
import java.io.PrintWriter
import java.io.StringWriter

/**
 * Keeps at most one consented crash report until Flutter confirms delivery.
 * No stable installation or device identifier is created or stored.
 */
object AnonymousCrashStore {
    private const val PREFS_NAME = "anonymous_crash_reporting"
    private const val ENABLED_KEY = "enabled"
    private const val QUEUED_REPORT_KEY = "queued_report"
    private const val LAST_EXIT_TIMESTAMP_KEY = "last_exit_timestamp"
    private const val MAX_QUEUED_BYTES = 12_000
    private const val MAX_TRACE_CHARS = 4_000

    fun setEnabled(context: Context, enabled: Boolean) {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val wasEnabled = preferences.getBoolean(ENABLED_KEY, false)
        preferences.edit().apply {
            putBoolean(ENABLED_KEY, enabled)
            if (!enabled) remove(QUEUED_REPORT_KEY)
            // A report created before explicit consent must never be uploaded
            // if the user enables reporting later.
            if (!enabled || !wasEnabled) {
                putLong(LAST_EXIT_TIMESTAMP_KEY, System.currentTimeMillis())
            }
        }.apply()
    }

    fun store(context: Context, report: Map<*, *>): Boolean {
        return storeReport(context, report, immediate = false)
    }

    private fun storeReport(
        context: Context,
        report: Map<*, *>,
        immediate: Boolean,
    ): Boolean {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(ENABLED_KEY, false)) return false
        val json = runCatching { JSONObject(report).toString() }.getOrNull() ?: return false
        if (json.toByteArray(Charsets.UTF_8).size > MAX_QUEUED_BYTES) return false
        val edit = preferences.edit().putString(QUEUED_REPORT_KEY, json)
        // An uncaught exception normally terminates the process immediately
        // after this handler returns, so that one write must reach disk now.
        return if (immediate) edit.commit() else {
            edit.apply()
            true
        }
    }

    fun storeUnhandledJavaCrash(context: Context, thread: Thread, error: Throwable) {
        val writer = StringWriter()
        runCatching { error.printStackTrace(PrintWriter(writer)) }
        val now = System.currentTimeMillis()
        val isTelevision =
            context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK ==
                Configuration.UI_MODE_TYPE_TELEVISION
        storeReport(
            context,
            linkedMapOf(
                "report_id" to "java-$now-${thread.id}",
                "kind" to "java",
                "message" to sanitize(
                    "${error.javaClass.simpleName}: ${error.message.orEmpty()}",
                    500,
                ),
                "stack" to sanitizeStack(writer.toString(), MAX_TRACE_CHARS),
                "occurred_at_ms" to now,
                "android_sdk" to Build.VERSION.SDK_INT,
                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
                "device_class" to if (isTelevision) "tv" else "phone",
            ),
            immediate = true,
        )
    }

    fun pending(context: Context): Map<String, Any?>? {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!preferences.getBoolean(ENABLED_KEY, false)) return null
        preferences.getString(QUEUED_REPORT_KEY, null)?.let { encoded ->
            decode(encoded)?.let { return it }
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null

        val lastTimestamp = preferences.getLong(LAST_EXIT_TIMESTAMP_KEY, 0L)
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val exit = activityManager
            .getHistoricalProcessExitReasons(context.packageName, 0, 10)
            .asSequence()
            .filter { it.timestamp > lastTimestamp && isReportableReason(it.reason) }
            .minByOrNull { it.timestamp }
            ?: return null
        val reportId = "android-exit-${exit.timestamp}-${exit.reason}"
        val kind = when (exit.reason) {
            ApplicationExitInfo.REASON_ANR -> "anr"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "native"
            else -> "java"
        }
        val message = when (exit.reason) {
            ApplicationExitInfo.REASON_ANR -> "Android reported that TetoTV stopped responding."
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "Android reported a native TetoTV process crash."
            else -> "Android reported an unhandled TetoTV process crash."
        }
        val trace = runCatching {
            exit.traceInputStream?.bufferedReader()?.use { reader ->
                val buffer = CharArray(MAX_TRACE_CHARS)
                val count = reader.read(buffer)
                if (count > 0) String(buffer, 0, count) else ""
            }
        }.getOrNull().orEmpty()
        val details = listOfNotNull(
            sanitize(exit.description.orEmpty(), 700).takeIf { it.isNotEmpty() },
            sanitizeStack(trace, MAX_TRACE_CHARS).takeIf { it.isNotEmpty() },
        ).joinToString(" | ")
        val isTelevision =
            context.resources.configuration.uiMode and Configuration.UI_MODE_TYPE_MASK ==
                Configuration.UI_MODE_TYPE_TELEVISION
        return linkedMapOf(
            "report_id" to reportId,
            "kind" to kind,
            "message" to message,
            "stack" to details,
            "occurred_at_ms" to exit.timestamp,
            "android_sdk" to Build.VERSION.SDK_INT,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"),
            "device_class" to if (isTelevision) "tv" else "phone",
        )
    }

    fun acknowledge(context: Context, reportId: String) {
        val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val queued = preferences.getString(QUEUED_REPORT_KEY, null)
        if (queued != null && decode(queued)?.get("report_id") == reportId) {
            preferences.edit()
                .remove(QUEUED_REPORT_KEY)
                .putLong(LAST_EXIT_TIMESTAMP_KEY, System.currentTimeMillis())
                .apply()
            return
        }
        val match = Regex("^android-exit-(\\d+)-\\d+$").matchEntire(reportId) ?: return
        val timestamp = match.groupValues[1].toLongOrNull() ?: return
        val current = preferences.getLong(LAST_EXIT_TIMESTAMP_KEY, 0L)
        if (timestamp > current) {
            preferences.edit().putLong(LAST_EXIT_TIMESTAMP_KEY, timestamp).apply()
        }
    }

    fun clear(context: Context) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(QUEUED_REPORT_KEY)
            .putLong(LAST_EXIT_TIMESTAMP_KEY, System.currentTimeMillis())
            .apply()
    }

    internal fun isReportableReason(reason: Int): Boolean =
        reason == ApplicationExitInfo.REASON_CRASH ||
            reason == ApplicationExitInfo.REASON_CRASH_NATIVE ||
            reason == ApplicationExitInfo.REASON_ANR

    private fun decode(value: String): Map<String, Any?>? = runCatching {
        val objectValue = JSONObject(value)
        buildMap {
            for (key in objectValue.keys()) {
                put(key, objectValue.opt(key).takeUnless { it === JSONObject.NULL })
            }
        }
    }.getOrNull()

    internal fun sanitize(value: String, maximum: Int): String {
        var output = value
            .replace(Regex("https?://[^\\s\\\"']+", RegexOption.IGNORE_CASE), "[URL]")
            .replace(Regex("magnet:\\?[^\\s\\\"']+", RegexOption.IGNORE_CASE), "[MAGNET]")
            .replace(
                Regex(
                    "\\b(?![A-Za-z]:[\\\\/])[A-Za-z][A-Za-z0-9+.-]{0,31}:(?![0-9\\s])[^\\s\\\"'<>]+",
                    RegexOption.IGNORE_CASE,
                ),
                "[URI]",
            )
            .replace(
                Regex(
                    "(^|[\\s\\\"'(=\\[])(?:[A-Za-z]:[\\\\/]|\\\\\\\\[^\\\\/\\s\\\"'<>]+[\\\\/])[^\\r\\n\\\"'<>]*",
                )
            ) { match -> "${match.groupValues[1]}[PATH]" }
            .replace(Regex("(^|[\\s\\\"'(=\\[])/(?!/)[^\\r\\n\\\"'<>]*")) { match ->
                "${match.groupValues[1]}[PATH]"
            }
            .replace(Regex("\\bgithub_pat_[A-Za-z0-9_]+\\b", RegexOption.IGNORE_CASE), "[REDACTED]")
            .replace(Regex("\\bgh[pousr]_[A-Za-z0-9]{20,}\\b", RegexOption.IGNORE_CASE), "[REDACTED]")
            .replace(Regex("\\beyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\b"), "[REDACTED]")
            .replace(Regex("bearer\\s+[^\\s,;\\\"']+", RegexOption.IGNORE_CASE), "Bearer [REDACTED]")
            .replace(
                Regex(
                    "(?:authorization|access[_ -]?token|refresh[_ -]?token|token|api[_ -]?key|client[_ -]?secret|password)\\s*[:=]\\s*[^\\s,;\\\"']+",
                    RegexOption.IGNORE_CASE,
                ),
                "[REDACTED]",
            )
            .replace(Regex("\\b[a-fA-F0-9]{40,}\\b"), "[REDACTED]")
            .replace(Regex("[\\r\\n]+"), " ")
            .trim()
        if (output.length > maximum) output = output.substring(0, maximum)
        return output
    }

    internal fun sanitizeStack(value: String, maximum: Int): String {
        val output = value
            .lineSequence()
            .take(50)
            .map { sanitize(it, 300) }
            .filter { it.isNotEmpty() }
            .joinToString("\n")
        return if (output.length <= maximum) output else output.substring(0, maximum)
    }
}
