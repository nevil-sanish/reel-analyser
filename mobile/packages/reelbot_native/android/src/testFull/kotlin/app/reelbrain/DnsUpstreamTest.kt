package app.reelbrain

import java.net.InetAddress
import org.junit.Assert.assertEquals
import org.junit.Test

class DnsUpstreamTest {
    private fun ip(s: String) = InetAddress.getByName(s)
    private fun names(l: List<InetAddress>) = l.map { it.hostAddress }

    @Test fun ipv6OnlyNetworkKeepsItsServerFirst() {
        assertEquals(listOf("2405:200:800:0:0:0:0:11", "1.1.1.1", "8.8.8.8"), names(DnsUpstream.order(listOf(ip("2405:200:800::11")), "10.111.222.1")))
    }

    @Test fun neverAsksTheFilterItself() {
        assertEquals(listOf("192.168.1.1", "1.1.1.1", "8.8.8.8"), names(DnsUpstream.order(listOf(ip("10.111.222.1"), ip("192.168.1.1")), "10.111.222.1")))
    }

    @Test fun noServersStillHasPublicOnes() {
        assertEquals(listOf("1.1.1.1", "8.8.8.8"), names(DnsUpstream.order(emptyList(), "10.111.222.1")))
    }

    @Test fun duplicatesAndTheCapAreHandled() {
        assertEquals(listOf("8.8.8.8", "1.1.1.1"), names(DnsUpstream.order(listOf(ip("8.8.8.8"), ip("8.8.8.8")), "10.111.222.1")))
        assertEquals(2, DnsUpstream.order(listOf(ip("9.9.9.9"), ip("9.9.9.10")), "10.111.222.1", max = 2).size)
    }
}
