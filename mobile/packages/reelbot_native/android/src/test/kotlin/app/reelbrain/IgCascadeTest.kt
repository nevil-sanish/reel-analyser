package app.reelbrain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class IgCascadeTest {
    private var now = 0L
    private val slept = mutableListOf<Long>()
    private fun cascade() = IgCascade(clock = { now }, sleep = { slept += it; now += it })

    private val video = StepResult.Media(IgMedia(videoUrl = "v.mp4", author = "a"))
    private val meta = StepResult.Media(IgMedia(caption = "cap", thumbnailUrl = "t.jpg"))

    // T-IG-U04
    @Test fun firstVideoStopsTheCascade() {
        val calls = mutableListOf<Int>()
        val steps = (1..6).map { i -> { _: String -> calls += i; if (i == 1) video else StepResult.Empty } }
        val r = cascade().run("c", steps)
        assertEquals(listOf(1), calls)
        assertEquals(1, r.step)
        assertTrue(r.media.hasVideo)
    }

    @Test fun metadataOnlyReportsTheStepThatFoundIt() {
        val steps = (1..5).map { i -> { _: String -> if (i == 5) meta else StepResult.Empty } }
        val r = cascade().run("c", steps)
        assertEquals(5, r.step)
        assertEquals("cap", r.media.caption)
        assertFalse(r.media.hasVideo)
    }

    @Test fun laterVideoKeepsEarlierMetadata() {
        val r = cascade().run("c", listOf({ _ -> meta }, { _ -> video }))
        assertEquals(2, r.step)
        assertEquals("cap", r.media.caption)
        assertEquals("v.mp4", r.media.videoUrl)
    }

    // T-IG-U05
    @Test fun requestsAreOneSecondApart() {
        val c = cascade()
        c.throttle()
        now += 400
        c.throttle()
        assertEquals(listOf(600L), slept)
    }

    @Test fun rateLimitPausesInstagramForTwoMinutes() {
        val c = cascade()
        try { c.run("a", listOf { _ -> StepResult.Limited }); fail() } catch (_: RateLimitedException) {}
        val calls = AtomicInteger()
        now += 90_000
        try { c.run("b", listOf { _ -> calls.incrementAndGet(); video }); fail() } catch (_: RateLimitedException) {}
        try { c.throttle(); fail() } catch (_: RateLimitedException) {}
        assertEquals(0, calls.get())
        now += 60_000
        assertEquals(1, c.run("b", listOf { _ -> calls.incrementAndGet(); video }).step)
    }

    // T-IG-U08
    @Test fun loginWallOnOneStepOnlySkipsThatStep() {
        val c = cascade()
        val r = c.run("a", listOf({ _ -> StepResult.LoginWall }, { _ -> video }))
        assertEquals(2, r.step)
        c.throttle() // not paused
    }

    @Test fun allWalledRetriesInTenMinutesThenGivesUp() {
        val c = cascade()
        val walls = listOf<(String) -> StepResult>({ _ -> StepResult.LoginWall }, { _ -> StepResult.Empty })
        try { c.run("a", walls); fail() } catch (_: RateLimitedException) {}
        now += 11 * 60_000
        try { c.run("a", walls); fail() } catch (_: RateLimitedException) {}
        now += 11 * 60_000
        assertEquals(0, c.run("a", walls).step) // third time: give up, the runner makes do
    }

    // T-IG-U06
    @Test fun privatePostIsNotRetriedForTenMinutes() {
        val c = cascade()
        val calls = AtomicInteger()
        val steps = listOf { _: String -> calls.incrementAndGet(); StepResult.Gone }
        c.run("priv", steps)
        now += 9 * 60_000
        c.run("priv", steps)
        assertEquals(1, calls.get())
        c.run("other", steps)
        assertEquals(2, calls.get())
        now += 2 * 60_000
        c.run("priv", steps)
        assertEquals(3, calls.get())
    }

    // T-IG-U07
    @Test fun concurrentFetchesOfOneCodeShareOneRun() {
        val c = IgCascade()
        val calls = AtomicInteger()
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val steps = listOf { _: String -> calls.incrementAndGet(); entered.countDown(); release.await(); video }
        val pool = Executors.newFixedThreadPool(2)
        val a = pool.submit<FetchResult> { c.run("same", steps) }
        entered.await(5, TimeUnit.SECONDS)
        val b = pool.submit<FetchResult> { c.run("same", steps) }
        Thread.sleep(100)
        release.countDown()
        assertEquals(a.get(), b.get())
        assertEquals(1, calls.get())
        pool.shutdown()
    }
}
