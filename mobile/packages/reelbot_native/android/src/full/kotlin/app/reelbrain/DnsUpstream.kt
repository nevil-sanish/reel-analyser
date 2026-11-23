package app.reelbrain

import java.net.InetAddress

/**
 * Which DNS servers the website filter asks, in order. The phone's own servers come first (IPv4 and IPv6: a mobile network can have
 * only an IPv6 one), the filter's own address never, and two public servers last, so one dead server does not take the internet
 * with it. Pure Kotlin so it is tested on the JVM.
 */
object DnsUpstream {
    private val fallback = listOf("1.1.1.1", "8.8.8.8")

    fun order(system: List<InetAddress>, local: String, max: Int = 4): List<InetAddress> =
        (system.filter { it.hostAddress != local && !it.isAnyLocalAddress } + fallback.map { InetAddress.getByName(it) })
            .distinctBy { it.hostAddress }.take(max)
}
