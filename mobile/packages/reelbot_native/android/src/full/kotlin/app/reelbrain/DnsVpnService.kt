package app.reelbrain

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.Executors

/**
 * The website filter (full build): a local VPN that only carries DNS questions, as DNS66 and BlockAds do. A look-up for a site
 * whose daily time is used up gets "no such name"; every other question is passed to the phone's normal DNS server and the answer
 * handed back. No other traffic enters the VPN, nothing leaves the phone except those same questions to the same DNS server,
 * and no screen is read.
 */
class DnsVpnService : VpnService() {
    companion object {
        @Volatile var running = false
        private const val LOCAL_DNS = "10.111.222.1"
        private const val FALLBACK_DNS = "1.1.1.1"
    }

    private var tun: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private val pool = Executors.newFixedThreadPool(16)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (tun == null) start()
        return START_STICKY
    }

    /** The DNS server the phone used before the VPN: the questions go on to it, so nobody new sees them. */
    private fun upstream(): InetAddress {
        val cm = getSystemService(ConnectivityManager::class.java)
        val dns = cm.getLinkProperties(cm.activeNetwork)?.dnsServers?.firstOrNull { it.address.size == 4 && it.hostAddress != LOCAL_DNS }
        return dns ?: InetAddress.getByName(FALLBACK_DNS)
    }

    private fun start() {
        val up = upstream()
        val fd = Builder().setSession("Reel Analyser + Blocker site limits")
            .addAddress("10.111.222.2", 32).addDnsServer(LOCAL_DNS).addRoute(LOCAL_DNS, 32)
            .setBlocking(true).establish() ?: return stopSelf()
        tun = fd
        running = true
        val out = FileOutputStream(fd.fileDescriptor)
        reader = Thread {
            val inp = FileInputStream(fd.fileDescriptor)
            val buf = ByteArray(32767)
            try {
                while (!Thread.interrupted()) {
                    val n = inp.read(buf)
                    if (n <= 0) continue
                    val q = DnsPacket.parse(buf, n) ?: continue
                    pool.execute { answer(q, up, out) }
                }
            } catch (e: Exception) {
                // the VPN was stopped
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun answer(q: DnsPacket.Query, up: InetAddress, out: FileOutputStream) {
        try {
            val resp = if (SiteFilter.onQuery(q.name, System.currentTimeMillis())) DnsPacket.nxdomain(q.dns) else forward(q.dns, up) ?: return
            val pkt = DnsPacket.reply(q, resp)
            synchronized(out) { out.write(pkt) }
        } catch (e: Exception) {
            // one lost question: the app asks again
        }
    }

    private fun forward(dns: ByteArray, up: InetAddress): ByteArray? = DatagramSocket().use { s ->
        protect(s) // this socket must not enter the VPN again
        s.soTimeout = 4000
        s.send(DatagramPacket(dns, dns.size, up, 53))
        val b = ByteArray(4096)
        val p = DatagramPacket(b, b.size)
        s.receive(p)
        b.copyOf(p.length)
    }

    override fun onRevoke() = stopSelf()

    override fun onDestroy() {
        running = false
        reader?.interrupt()
        tun?.close()
        tun = null
        pool.shutdownNow()
        super.onDestroy()
    }
}

/** Starts or stops the filter to match the limits: on only while a website has a limit and the user has allowed the VPN. */
object SiteFilterControl {
    fun sync(ctx: Context, wanted: Boolean) {
        val i = Intent(ctx, DnsVpnService::class.java)
        if (wanted && VpnService.prepare(ctx) == null) {
            runCatching { ctx.startService(i) }
        } else if (!wanted) {
            ctx.stopService(i)
        }
    }
}
