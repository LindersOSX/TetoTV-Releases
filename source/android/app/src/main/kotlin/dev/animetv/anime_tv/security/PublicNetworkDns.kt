package dev.animetv.anime_tv.security

import java.net.InetAddress
import java.net.UnknownHostException
import okhttp3.Dns

/**
 * DNS wrapper for URLs supplied by debrid services or third-party add-ons.
 *
 * Filtering the actual resolution result on every OkHttp lookup prevents a
 * hostname from passing an earlier URL check and later rebinding to the TV,
 * phone, emulator host, or another device on the local network.
 */
internal class PublicNetworkDns(
    private val delegate: Dns = Dns.SYSTEM,
) : Dns {
    override fun lookup(hostname: String): List<InetAddress> {
        val publicAddresses = delegate.lookup(hostname)
            .filter(NetworkRequestPolicy::isPublicNetworkAddress)
        if (publicAddresses.isEmpty()) {
            throw UnknownHostException("The media host did not resolve to a public address.")
        }
        return publicAddresses
    }
}
