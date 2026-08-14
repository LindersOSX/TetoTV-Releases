package dev.animetv.anime_tv.security

import java.net.URI
import java.net.InetAddress
import java.util.Locale

/**
 * Security policy for URLs and headers supplied by Flutter or third-party
 * source add-ons before they reach a native Android media stack.
 */
internal object NetworkRequestPolicy {
    private const val MAX_HEADER_COUNT = 32
    private const val MAX_HEADER_NAME_LENGTH = 100
    private const val MAX_HEADER_VALUE_LENGTH = 8_192
    private const val MAX_DIAGNOSTIC_LENGTH = 800
    private val OPAQUE_PLAYBACK_CAPABILITY = Regex("^[A-Za-z0-9_-]{32}$")

    private val blockedRequestHeaders = setOf(
        "accept-encoding",
        "connection",
        "content-length",
        "expect",
        "host",
        "keep-alive",
        "proxy-connection",
        "range",
        "te",
        "trailer",
        "transfer-encoding",
        "upgrade",
    )

    // These headers do not contain account credentials and are commonly
    // required by CDN redirects or cross-origin HLS segments.
    private val crossOriginSafeHeaders = setOf(
        "accept",
        "accept-language",
        "origin",
        "referer",
        "user-agent",
    )

    private val uriPattern = Regex("(?i)https://[^\\s\\]>)\"']+")
    private val authorizationPattern = Regex(
        "(?i)\\b(authorization|proxy-authorization)" +
            "\\b\\s*[:=]\\s*[^\\r\\n,;)]+",
    )
    private val credentialPattern = Regex(
        "(?i)\\b(cookie|set-cookie|" +
            "x-api-key|api[-_]?key|access[-_]?token|refresh[-_]?token)" +
            "\\b\\s*[:=]\\s*[^\\s,;]+",
    )

    data class Origin(
        val scheme: String,
        val host: String,
        val port: Int,
    )

    fun httpsOrigin(value: String): Origin? = runCatching {
        val uri = URI(value.trim())
        if (!uri.scheme.equals("https", ignoreCase = true)) return@runCatching null
        if (uri.rawUserInfo != null) return@runCatching null
        val host = uri.host?.trim()?.lowercase(Locale.ROOT).orEmpty()
            .removePrefix("[")
            .removeSuffix("]")
        if (host.isEmpty()) return@runCatching null
        val port = when (uri.port) {
            -1 -> 443
            in 1..65_535 -> uri.port
            else -> return@runCatching null
        }
        Origin("https", host, port)
    }.getOrNull()

    /**
     * Accepts a media URL explicitly supplied by the viewer from the Local
     * media/Jellyfin screen. Cleartext is limited to numeric private-network
     * addresses (plus localhost), avoiding DNS rebinding and arbitrary HTTP.
     */
    fun trustedLocalMediaOrigin(value: String): Origin? = runCatching {
        val uri = URI(value.trim())
        val scheme = uri.scheme?.lowercase(Locale.ROOT).orEmpty()
        if (scheme !in setOf("http", "https")) return@runCatching null
        if (uri.rawUserInfo != null || uri.host.isNullOrBlank()) return@runCatching null
        val host = uri.host.trim().lowercase(Locale.ROOT)
            .removePrefix("[")
            .removeSuffix("]")
        val port = when (uri.port) {
            -1 -> if (scheme == "https") 443 else 80
            in 1..65_535 -> uri.port
            else -> return@runCatching null
        }
        if (scheme == "http" && !isExplicitPrivateHost(host)) {
            return@runCatching null
        }
        Origin(scheme, host, port)
    }.getOrNull()

    /**
     * Accepts only the opaque loopback capability shape issued by TetoTV's
     * in-process web playback proxy. The Flutter bridge sets the matching
     * trust bit only after checking that the capability is currently active.
     */
    fun trustedPlaybackProxyOrigin(value: String): Origin? = runCatching {
        val uri = URI(value.trim())
        if (!uri.scheme.equals("http", ignoreCase = true) ||
            uri.rawUserInfo != null ||
            uri.host != "127.0.0.1" ||
            uri.port !in 1..65_535 ||
            uri.rawQuery != null ||
            uri.rawFragment != null
        ) {
            return@runCatching null
        }
        val segments = uri.path.split('/').filter(String::isNotEmpty)
        if (segments.size != 4 ||
            segments[0] != "tetotv-web" ||
            segments[1] != "v1" ||
            !OPAQUE_PLAYBACK_CAPABILITY.matches(segments[2]) ||
            !OPAQUE_PLAYBACK_CAPABILITY.matches(segments[3])
        ) {
            return@runCatching null
        }
        Origin("http", "127.0.0.1", uri.port)
    }.getOrNull()

    fun isTrustedContentUri(value: String): Boolean = runCatching {
        val uri = URI(value.trim())
        uri.scheme.equals("content", ignoreCase = true) &&
            !uri.rawAuthority.isNullOrBlank() &&
            uri.rawUserInfo == null &&
            uri.rawFragment == null
    }.getOrDefault(false)

    fun origin(scheme: String, host: String, port: Int): Origin = Origin(
        scheme = scheme.lowercase(Locale.ROOT),
        host = host.lowercase(Locale.ROOT),
        port = port,
    )

    fun sanitizeRequestHeaders(values: Map<String, String>): Map<String, String> {
        val sanitized = linkedMapOf<String, String>()
        for ((rawName, rawValue) in values) {
            val name = rawName.trim()
            val normalizedName = name.lowercase(Locale.ROOT)
            val value = rawValue.trim()
            if (
                name.isEmpty() ||
                name.length > MAX_HEADER_NAME_LENGTH ||
                !name.all(::isHeaderNameCharacter) ||
                normalizedName in blockedRequestHeaders ||
                value.length > MAX_HEADER_VALUE_LENGTH ||
                !value.all(::isHeaderValueCharacter)
            ) continue

            // HTTP field names are case-insensitive. Retain only the last
            // supplied value so add-ons cannot smuggle duplicate credentials.
            sanitized.keys.firstOrNull { it.equals(name, ignoreCase = true) }
                ?.let(sanitized::remove)
            if (sanitized.size >= MAX_HEADER_COUNT) continue
            sanitized[name] = value
        }
        return sanitized
    }

    fun shouldForwardHeader(
        headerName: String,
        sourceOrigin: Origin,
        requestOrigin: Origin,
    ): Boolean =
        sourceOrigin == requestOrigin ||
            headerName.lowercase(Locale.ROOT) in crossOriginSafeHeaders

    /**
     * Returns true only for addresses that are safe for an untrusted media URL
     * to contact. This check is deliberately applied to the DNS answer used by
     * OkHttp, not only to a URL preflight, so a redirect or DNS rebinding cannot
     * turn a public-looking stream into a request to the device or LAN.
     */
    fun isPublicNetworkAddress(address: InetAddress): Boolean {
        if (
            address.isAnyLocalAddress ||
            address.isLoopbackAddress ||
            address.isLinkLocalAddress ||
            address.isSiteLocalAddress ||
            address.isMulticastAddress
        ) return false

        val bytes = address.address
        return when (bytes.size) {
            4 -> isPublicIpv4(bytes)
            16 -> isPublicIpv6(bytes)
            else -> false
        }
    }

    /** Removes expiring debrid URLs and credentials from user-visible errors. */
    fun redactNetworkDiagnostic(value: String?): String? {
        if (value.isNullOrBlank()) return null
        val withoutUris = uriPattern.replace(value, "https://[redacted]")
        val withoutAuthorization = authorizationPattern.replace(withoutUris) { match ->
            "${match.groupValues[1]}=[redacted]"
        }
        val withoutCredentials = credentialPattern.replace(withoutAuthorization) { match ->
            "${match.groupValues[1]}=[redacted]"
        }
        return withoutCredentials.take(MAX_DIAGNOSTIC_LENGTH)
    }

    private fun isHeaderNameCharacter(value: Char): Boolean =
        value in 'a'..'z' ||
            value in 'A'..'Z' ||
            value in '0'..'9' ||
            value in "!#$%&'*+-.^_`|~"

    private fun isHeaderValueCharacter(value: Char): Boolean =
        value == '\t' || value.code in 0x20..0x7E

    private fun isPublicIpv4(bytes: ByteArray): Boolean {
        val first = bytes[0].toInt() and 0xFF
        val second = bytes[1].toInt() and 0xFF
        val third = bytes[2].toInt() and 0xFF
        return when {
            // Current network, private-use, shared address space, loopback.
            first == 0 -> false
            first == 10 -> false
            first == 100 && second in 64..127 -> false
            first == 127 -> false
            // Link-local and RFC 1918.
            first == 169 && second == 254 -> false
            first == 172 && second in 16..31 -> false
            first == 192 && second == 168 -> false
            // IETF protocol assignments, documentation, deprecated anycast,
            // benchmarking, and TEST-NET address blocks.
            first == 192 && second == 0 && third == 0 -> false
            first == 192 && second == 0 && third == 2 -> false
            first == 192 && second == 88 && third == 99 -> false
            first == 198 && second in 18..19 -> false
            first == 198 && second == 51 && third == 100 -> false
            first == 203 && second == 0 && third == 113 -> false
            // Multicast, future/reserved use, and limited broadcast.
            first >= 224 -> false
            else -> true
        }
    }

    private fun isPublicIpv6(bytes: ByteArray): Boolean {
        val first = bytes[0].toInt() and 0xFF
        val second = bytes[1].toInt() and 0xFF

        // Reject IPv4-compatible and IPv4-mapped forms. Android commonly
        // normalizes mapped literals to Inet4Address, but checking the raw
        // representation keeps this policy safe across runtimes.
        if (bytes.take(10).all { it == 0.toByte() }) {
            val mapped = bytes[10] == 0xFF.toByte() && bytes[11] == 0xFF.toByte()
            val compatible = bytes[10] == 0.toByte() && bytes[11] == 0.toByte()
            if (mapped || compatible) return false
        }

        // RFC 8215 reserves 64:ff9b:1::/48 for local-use NAT64. A DNS answer
        // in this range can translate to a LAN IPv4 target on networks that
        // route the prefix, so it must never be treated as public media.
        val nat64LocalUse =
            bytes[0] == 0x00.toByte() &&
                bytes[1] == 0x64.toByte() &&
                bytes[2] == 0xFF.toByte() &&
                bytes[3] == 0x9B.toByte() &&
                bytes[4] == 0x00.toByte() &&
                bytes[5] == 0x01.toByte()
        if (nat64LocalUse) return false

        return when {
            // Unique-local fc00::/7.
            first and 0xFE == 0xFC -> false
            // Link-local fe80::/10 and deprecated site-local fec0::/10.
            first == 0xFE && second and 0xC0 == 0x80 -> false
            first == 0xFE && second and 0xC0 == 0xC0 -> false
            // IPv6 multicast ff00::/8.
            first == 0xFF -> false
            else -> true
        }
    }

    private fun isExplicitPrivateHost(host: String): Boolean {
        if (host == "localhost") return true
        // HTTP Jellyfin addresses deliberately require an IP literal. Hostname
        // resolution here would allow a public name to rebind to the LAN.
        val literal = host.removePrefix("[").removeSuffix("]").substringBefore('%')
        val numericLiteral = when {
            literal.contains(':') -> literal.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' || it == ':' || it == '.' }
            literal.contains('.') -> literal.all { it.isDigit() || it == '.' }
            else -> false
        }
        if (!numericLiteral) return false
        val address = runCatching { InetAddress.getByName(literal) }.getOrNull()
            ?: return false
        return !address.isAnyLocalAddress &&
            !address.isMulticastAddress &&
            (address.isLoopbackAddress ||
                address.isLinkLocalAddress ||
                address.isSiteLocalAddress ||
                isUniqueLocalIpv6(address.address))
    }

    private fun isUniqueLocalIpv6(bytes: ByteArray): Boolean =
        bytes.size == 16 && (bytes[0].toInt() and 0xFE) == 0xFC
}
