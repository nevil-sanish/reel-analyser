package app.reelbrain

import org.junit.Assert.*
import org.junit.Test
import java.util.Calendar

class BlockPolicyTest {
    private fun at(h: Int, m: Int, day: Int = 9) = Calendar.getInstance().apply {
        set(2026, Calendar.NOVEMBER, day, h, m, 0); set(Calendar.MILLISECOND, 0)
    }.timeInMillis

    private val min = 60_000L
    private val shared = BlockConfig("shared", setOf("instagram", "youtube"), mapOf("all" to BlockRule(30, emptyList())))
    private val separate = BlockConfig("separate", setOf("instagram", "youtube", "browser"), mapOf(
        "instagram" to BlockRule(10, emptyList()), "youtube" to BlockRule(null, listOf(Interval(18 * 60, 19 * 60))),
        "browser" to BlockRule(5, listOf(Interval(22 * 60, 2 * 60)))))

    private fun v(c: BlockConfig?, s: String, minute: Int, used: Map<String, Long> = emptyMap(), susp: Boolean = false) =
        BlockPolicy.verdict(c, s, minute, used, susp)

    @Test fun `no rules or a surface not in the list is never blocked`() {
        assertEquals(Verdict.Allow, v(null, "instagram", 0))
        assertEquals(Verdict.Allow, v(shared, "browser", 0, mapOf("browser" to 999 * min)))
    }

    @Test fun `shared limit adds the chosen items together`() {
        assertEquals(Verdict.Allow, v(shared, "instagram", 600, mapOf("instagram" to 20 * min, "youtube" to 9 * min)))
        assertEquals(Verdict.Block("limit"), v(shared, "youtube", 600, mapOf("instagram" to 20 * min, "youtube" to 10 * min)))
        assertEquals(Verdict.Block("limit"), v(shared, "instagram", 600, mapOf("youtube" to 30 * min)))
    }

    @Test fun `separate limits count each item alone`() {
        assertEquals(Verdict.Block("limit"), v(separate, "instagram", 600, mapOf("instagram" to 10 * min)))
        assertEquals(Verdict.Allow, v(separate, "instagram", 600, mapOf("youtube" to 500 * min)))
    }

    @Test fun `schedule allows only inside the intervals`() {
        assertEquals(Verdict.Allow, v(separate, "youtube", 18 * 60))
        assertEquals(Verdict.Allow, v(separate, "youtube", 18 * 60 + 59))
        assertEquals(Verdict.Block("schedule"), v(separate, "youtube", 19 * 60))
        assertEquals(Verdict.Block("schedule"), v(separate, "youtube", 17 * 60 + 59))
    }

    @Test fun `an interval over midnight works on both sides`() {
        assertEquals(Verdict.Allow, v(separate, "browser", 23 * 60))
        assertEquals(Verdict.Allow, v(separate, "browser", 30))
        assertEquals(Verdict.Block("schedule"), v(separate, "browser", 2 * 60))
        assertEquals(Verdict.Block("schedule"), v(separate, "browser", 12 * 60))
    }

    @Test fun `limit and schedule must both be met`() {
        val c = BlockConfig("shared", setOf("instagram"), mapOf("all" to BlockRule(10, listOf(Interval(600, 700)))))
        assertEquals(Verdict.Allow, v(c, "instagram", 650, mapOf("instagram" to 9 * min)))
        assertEquals(Verdict.Block("limit"), v(c, "instagram", 650, mapOf("instagram" to 10 * min)))
        assertEquals(Verdict.Block("schedule"), v(c, "instagram", 800, mapOf("instagram" to 1 * min)))
    }

    @Test fun `several intervals`() {
        val c = BlockConfig("shared", setOf("youtube"), mapOf("all" to BlockRule(null, listOf(Interval(480, 540), Interval(1200, 1260)))))
        assertEquals(Verdict.Allow, v(c, "youtube", 500))
        assertEquals(Verdict.Allow, v(c, "youtube", 1230))
        assertEquals(Verdict.Block("schedule"), v(c, "youtube", 700))
    }

    @Test fun `suspended for the day lets everything through`() {
        assertEquals(Verdict.Allow, v(shared, "instagram", 600, mapOf("instagram" to 999 * min), susp = true))
    }

    @Test fun `first set-up applies at once and later edits only in the window`() {
        val now = at(15, 0)
        val first = BlockPolicy.save(BlockState(), shared, now)!!
        assertEquals(shared, first.active)
        assertTrue(BlockPolicy.editable(BlockState(), now))
        assertFalse(BlockPolicy.editable(first, at(0, 10)))
        assertFalse(BlockPolicy.editable(first, now))
        assertNull(BlockPolicy.save(first, separate, now))
        assertTrue(BlockPolicy.editable(first, at(0, 9)))
    }

    @Test fun `an edit in the window starts at ten past midnight, not before`() {
        val s0 = BlockState(active = shared)
        val saved = BlockPolicy.save(s0, separate, at(0, 4))!!
        assertEquals(shared, BlockPolicy.effective(saved, at(0, 9)).active)
        assertEquals(separate, BlockPolicy.effective(saved, at(0, 10)).active)
        assertNull(BlockPolicy.effective(saved, at(5, 0)).pending)
    }

    @Test fun `json round trip and damaged values`() {
        assertEquals(separate, BlockConfig.parse(separate.toJson()))
        assertEquals(shared, BlockConfig.parse(shared.toJson()))
        assertNull(BlockConfig.parse(null))
        assertNull(BlockConfig.parse("nonsense"))
        assertNull(BlockConfig.parse("""{"mode":"x","items":[],"rules":{}}"""))
        val odd = BlockConfig.parse("""{"mode":"shared","items":["instagram","tiktok"],"rules":{"all":{"limitMin":99999,"intervals":[[5,5],[2000,3]]}}}""")!!
        assertEquals(setOf("instagram"), odd.items)
        assertNull(odd.rules["all"]!!.limitMin)
        assertTrue(odd.rules["all"]!!.intervals.isEmpty())
    }

    @Test fun `only the reels or shorts part of a browser site counts`() {
        assertTrue(BlockPolicy.browserSurface("instagram.com/reels/"))
        assertTrue(BlockPolicy.browserSurface("https://www.instagram.com/reel/Cabc/"))
        assertTrue(BlockPolicy.browserSurface("m.youtube.com/shorts/xyz"))
        assertFalse(BlockPolicy.browserSurface("instagram.com/"))
        assertFalse(BlockPolicy.browserSurface("youtube.com/watch?v=1"))
    }

    private class Sink : BlockMeter.Sink {
        val rows = mutableListOf<Triple<String, String, Long>>()
        override fun addUse(date: String, surface: String, ms: Long) { rows += Triple(date, surface, ms) }
        val total get() = rows.sumOf { it.third }
    }

    @Test fun `meter adds time while the surface stays on screen and skips gaps`() {
        val s = Sink(); val m = BlockMeter(s)
        m.observe(0, "instagram", "d"); m.observe(1000, "instagram", "d"); m.observe(3000, "instagram", "d")
        assertEquals(3000L, s.total + m.pending("instagram"))
        m.observe(20000, "instagram", "d") // a sleeping phone is not watch time
        m.stop()
        assertEquals(3000L, s.total)
    }

    @Test fun `meter switches surface and ends when reels are left`() {
        val s = Sink(); val m = BlockMeter(s)
        m.observe(0, "instagram", "d"); m.observe(2500, "instagram", "d")
        m.observe(3000, "youtube", "d"); m.observe(4000, "youtube", "d")
        m.observe(4500, null, "d")
        assertFalse(m.active)
        assertEquals(listOf("instagram", "youtube"), s.rows.map { it.second }.distinct())
        assertEquals(2500L, s.rows.filter { it.second == "instagram" }.sumOf { it.third })
    }
}
