package app.reelbrain

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.util.Log
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
    }

    /** The phone's real network (never this VPN) and the DNS servers to ask on it. Follows Wi-Fi and mobile data changes. */
    @Volatile private var net: Network? = null
    @Volatile private var servers: List<InetAddress> = DnsUpstream.order(emptyList(), LOCAL_DNS)
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var tun: ParcelFileDescriptor? = null
    private var reader: Thread? = null
    private val pool = Executors.newFixedThreadPool(16)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (tun == null) start()
        return START_STICKY
    }

    /** Picks the phone's real network (the default one, else any validated non-VPN one) and its DNS servers. */
    private fun refresh() {
        val cm = getSystemService(ConnectivityManager::class.java)
        fun real(n: Network?) = n?.takeIf { cm.getNetworkCapabilities(it)?.let { c ->
            !c.hasTransport(NetworkCapabilities.TRANSPORT_VPN) && c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } == true }
        val n = real(cm.activeNetwork) ?: cm.allNetworks.firstOrNull { real(it) != null && cm.getNetworkCapabilities(it)
            ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED) == true }
        net = n
        servers = DnsUpstream.order(n?.let { cm.getLinkProperties(it)?.dnsServers }.orEmpty(), LOCAL_DNS)
        runCatching { setUnderlyingNetworks(n?.let { arrayOf(it) }) }
    }

    private fun start() {
        refresh()
        val cm = getSystemService(ConnectivityManager::class.java)
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = refresh()
            override fun onLost(network: Network) = refresh()
            override fun onLinkPropertiesChanged(network: Network, lp: android.net.LinkProperties) = refresh()
        }
        callback = cb
        cm.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), cb)
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
                    pool.execute { answer(q, out) }
                }
            } catch (e: Exception) {
                // the VPN was stopped
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun answer(q: DnsPacket.Query, out: FileOutputStream) {
        try {
            val resp = if (SiteFilter.onQuery(q.name, System.currentTimeMillis())) DnsPacket.nxdomain(q.dns) else forward(q.dns) ?: return
            val pkt = DnsPacket.reply(q, resp)
            synchronized(out) { out.write(pkt) }
        } catch (e: Exception) {
            Log.w("ReelDns", "answer failed: $e")
        }
    }

    /** Asks the phone's servers one after the other on the real network until one answers. */
    private fun forward(dns: ByteArray): ByteArray? {
        for (up in servers) {
            try {
                return DatagramSocket().use { s ->
                    protect(s) // this socket must not enter the VPN again
                    net?.bindSocket(s)
                    s.soTimeout = 2500
                    s.send(DatagramPacket(dns, dns.size, up, 53))
                    val b = ByteArray(4096)
                    val p = DatagramPacket(b, b.size)
                    s.receive(p)
                    b.copyOf(p.length)
                }
            } catch (e: Exception) {
                Log.w("ReelDns", "server ${up.hostAddress} failed: $e")
            }
        }
        return null
    }

    override fun onRevoke() = stopSelf()

    override fun onDestroy() {
        running = false
        callback?.let { runCatching { getSystemService(ConnectivityManager::class.java).unregisterNetworkCallback(it) } }
        callback = null
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
        if (wanted && SiteMethod.get(ctx) == "vpn" && VpnService.prepare(ctx) == null) {
            runCatching { ctx.startService(i) }
        } else if (!wanted || SiteMethod.get(ctx) != "vpn") {
            ctx.stopService(i)
        }
    }
}
