package app.reelbrain

/**
 * The few bytes of IPv4, UDP and DNS the website filter needs. The filter only ever receives DNS questions (the VPN routes
 * nothing else), so anything else is ignored. Pure Kotlin so it is tested on the JVM.
 */
object DnsPacket {
    class Query(val src: ByteArray, val dst: ByteArray, val srcPort: Int, val dstPort: Int, val dns: ByteArray, val name: String)

    private fun u16(b: ByteArray, i: Int) = ((b[i].toInt() and 0xff) shl 8) or (b[i + 1].toInt() and 0xff)

    /** The question name ("www.example.com") and where the question section ends; null when it is not a plain question. */
    fun question(dns: ByteArray): Pair<String, Int>? {
        if (dns.size < 17 || u16(dns, 4) < 1) return null
        var i = 12
        val sb = StringBuilder()
        while (true) {
            if (i >= dns.size) return null
            val n = dns[i].toInt() and 0xff
            if (n == 0) { i++; break }
            if (n and 0xc0 != 0 || i + 1 + n > dns.size) return null // compression never appears in a question
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 1..n) sb.append((dns[i + k].toInt() and 0xff).toChar().lowercaseChar())
            i += 1 + n
        }
        if (i + 4 > dns.size) return null
        return sb.toString() to i + 4
    }

    /** An IPv4 UDP packet to port 53 holding a DNS question, or null. */
    fun parse(pkt: ByteArray, len: Int): Query? {
        if (len < 28 || (pkt[0].toInt() shr 4) != 4) return null
        val ihl = (pkt[0].toInt() and 0x0f) * 4
        if (ihl < 20 || len < ihl + 8 || pkt[9].toInt() != 17) return null
        val dstPort = u16(pkt, ihl + 2)
        if (dstPort != 53) return null
        val udpLen = u16(pkt, ihl + 4)
        val end = minOf(len, ihl + udpLen)
        if (end <= ihl + 8) return null
        val dns = pkt.copyOfRange(ihl + 8, end)
        val (name, _) = question(dns) ?: return null
        return Query(pkt.copyOfRange(12, 16), pkt.copyOfRange(16, 20), u16(pkt, ihl), dstPort, dns, name)
    }

    /** The answer "this name does not exist": the question copied back with the response flags and code 3. */
    fun nxdomain(dns: ByteArray): ByteArray {
        val end = question(dns)?.second ?: dns.size
        val out = dns.copyOfRange(0, end)
        val rd = out[2].toInt() and 0x01
        out[2] = (0x80 or rd).toByte() // response, query kind 0, recursion desired as asked
        out[3] = 0x83.toByte() // recursion available, name error
        for (i in 6..11) out[i] = 0 // no answer, authority or extra records
        return out
    }

    private fun checksum(b: ByteArray, len: Int): Int {
        var sum = 0
        var i = 0
        while (i < len) { sum += u16(b, i); i += 2 }
        while (sum > 0xffff) sum = (sum and 0xffff) + (sum shr 16)
        return sum.inv() and 0xffff
    }

    /** The packet that carries [dnsResponse] back to the app that asked [q]. */
    fun reply(q: Query, dnsResponse: ByteArray): ByteArray {
        val total = 28 + dnsResponse.size
        val p = ByteArray(total)
        p[0] = 0x45; p[2] = (total shr 8).toByte(); p[3] = total.toByte()
        p[6] = 0x40 // do not fragment
        p[8] = 64; p[9] = 17
        q.dst.copyInto(p, 12); q.src.copyInto(p, 16)
        val c = checksum(p, 20)
        p[10] = (c shr 8).toByte(); p[11] = c.toByte()
        p[20] = (q.dstPort shr 8).toByte(); p[21] = q.dstPort.toByte()
        p[22] = (q.srcPort shr 8).toByte(); p[23] = q.srcPort.toByte()
        val ul = 8 + dnsResponse.size
        p[24] = (ul shr 8).toByte(); p[25] = ul.toByte() // UDP checksum 0 = none, allowed over IPv4
        dnsResponse.copyInto(p, 28)
        return p
    }
}
