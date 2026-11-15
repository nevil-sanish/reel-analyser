package app.reelbrain

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class DnsPacketTest {
    private fun dnsQuestion(name: String): ByteArray {
        val h = byteArrayOf(0x12, 0x34, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0)
        val labels = name.split('.').flatMap { l -> listOf(l.length.toByte()) + l.map { it.code.toByte() } } + 0.toByte()
        return h + labels.toByteArray() + byteArrayOf(0, 1, 0, 1)
    }

    private fun ipUdp(dns: ByteArray, dport: Int = 53): ByteArray {
        val total = 28 + dns.size
        val p = ByteArray(total)
        p[0] = 0x45; p[2] = (total shr 8).toByte(); p[3] = total.toByte(); p[8] = 64; p[9] = 17
        byteArrayOf(10, 0, 0, 2).copyInto(p, 12); byteArrayOf(10, 0, 0, 1).copyInto(p, 16)
        p[20] = 0x9c.toByte(); p[21] = 0x40; p[22] = (dport shr 8).toByte(); p[23] = dport.toByte()
        val ul = 8 + dns.size; p[24] = (ul shr 8).toByte(); p[25] = ul.toByte()
        dns.copyInto(p, 28)
        return p
    }

    @Test fun readsTheNameOfAQuestion() {
        val q = DnsPacket.parse(ipUdp(dnsQuestion("WWW.Example.com")).let { it }, 28 + dnsQuestion("www.example.com").size)
        assertNotNull(q)
        assertEquals("www.example.com", q!!.name)
        assertEquals(0x9c40, q.srcPort)
    }

    @Test fun ignoresWhatIsNotDnsOverUdpIpv4() {
        val d = dnsQuestion("a.com")
        assertNull(DnsPacket.parse(ipUdp(d, 80), 28 + d.size))
        assertNull(DnsPacket.parse(ByteArray(10), 10))
    }

    @Test fun nxdomainKeepsTheQuestionAndSetsTheCode() {
        val d = dnsQuestion("blocked.example")
        val r = DnsPacket.nxdomain(d)
        assertEquals(d.size, r.size)
        assertEquals(0x81.toByte(), r[2]) // response + recursion desired
        assertEquals(0x83.toByte(), r[3]) // recursion available + NXDOMAIN
        assertArrayEquals(byteArrayOf(0x12, 0x34), r.copyOfRange(0, 2)) // same id
        assertEquals(0, r[7].toInt()) // no answers
    }

    @Test fun replySwapsAddressesAndHasAValidHeaderChecksum() {
        val d = dnsQuestion("a.com")
        val q = DnsPacket.parse(ipUdp(d), 28 + d.size)!!
        val p = DnsPacket.reply(q, DnsPacket.nxdomain(d))
        assertArrayEquals(byteArrayOf(10, 0, 0, 1), p.copyOfRange(12, 16))
        assertArrayEquals(byteArrayOf(10, 0, 0, 2), p.copyOfRange(16, 20))
        var sum = 0
        for (i in 0 until 20 step 2) sum += ((p[i].toInt() and 0xff) shl 8) or (p[i + 1].toInt() and 0xff)
        while (sum > 0xffff) sum = (sum and 0xffff) + (sum shr 16)
        assertEquals(0xffff, sum)
        assertEquals(53, ((p[20].toInt() and 0xff) shl 8) or (p[21].toInt() and 0xff))
    }
}
