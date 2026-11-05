package app.reelbrain

import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.ExecutionException

/** What one cascade step found (PLAN §3.2). */
sealed interface StepResult {
    data class Media(val media: IgMedia) : StepResult
    object Empty : StepResult
    /** HTTP 429: Instagram is rate-limiting this phone; stop all Instagram calls for 30 min. */
    object Limited : StepResult
    /**
     * A login redirect or `require_login` on one page. v0.9.1: only that step is skipped; logged out, the post
     * page often walls while the embed player still works, and pausing everything for it made reels wait.
     */
    object LoginWall : StepResult
    /** Private, deleted or age-restricted. */
    object Gone : StepResult
}

data class FetchResult(val step: Int, val media: IgMedia)

class RateLimitedException : Exception("Instagram is rate-limiting; try later")

/**
 * The rules around the Instagram steps (ENDPOINTS §1): first video wins, metadata is merged,
 * one fetch per code at a time, 1 h negative cache, 30 min pause after a 429 (a login wall only skips its step),
 * and at most one request every 5 s. Steps are plain functions so tests can fake them.
 */
class IgCascade(
    private val clock: () -> Long = System::currentTimeMillis,
    private val sleep: (Long) -> Unit = Thread::sleep,
    private val minGapMs: Long = 5_000,
    private val pauseMs: Long = 30 * 60_000,
    private val negativeMs: Long = 60 * 60_000,
    private val wallRetryMs: Long = 10 * 60_000,
    private val wallTries: Int = 3,
) {
    /** Codes where every step was walled: retried after [wallRetryMs], given up after [wallTries] runs. */
    private val walled = ConcurrentHashMap<String, Int>()
    private val inFlight = ConcurrentHashMap<String, CompletableFuture<FetchResult>>()
    private val gone = ConcurrentHashMap<String, Long>()
    @Volatile private var pausedUntil = 0L
    private var nextRequestAt = 0L

    /** Call before every Instagram request. */
    fun throttle() {
        val wait: Long
        synchronized(this) {
            val now = clock()
            if (now < pausedUntil) throw RateLimitedException()
            val at = maxOf(now, nextRequestAt)
            nextRequestAt = at + minGapMs
            wait = at - now
        }
        if (wait > 0) sleep(wait)
    }

    fun run(code: String, steps: List<(String) -> StepResult>): FetchResult {
        val mine = CompletableFuture<FetchResult>()
        val existing = inFlight.putIfAbsent(code, mine)
        if (existing != null) {
            try { return existing.get() } catch (e: ExecutionException) { throw e.cause ?: e }
        }
        try {
            val r = runSteps(code, steps)
            mine.complete(r)
            return r
        } catch (e: Exception) {
            mine.completeExceptionally(e)
            throw e
        } finally {
            inFlight.remove(code)
        }
    }

    private fun runSteps(code: String, steps: List<(String) -> StepResult>): FetchResult {
        if (clock() < pausedUntil) throw RateLimitedException()
        gone[code]?.let { if (clock() - it < negativeMs) return FetchResult(0, IgMedia()) else gone.remove(code) }
        var best = IgMedia()
        var bestStep = 0
        var wall = false
        for ((i, step) in steps.withIndex()) {
            when (val r = step(code)) {
                is StepResult.Media -> {
                    if (bestStep == 0 && r.media.hasMeta || r.media.hasVideo) bestStep = i + 1
                    best = if (r.media.hasVideo) r.media.fill(best) else best.fill(r.media)
                    if (r.media.hasVideo) return FetchResult(i + 1, best)
                }
                StepResult.Empty -> Unit
                StepResult.Limited -> {
                    pausedUntil = clock() + pauseMs
                    throw RateLimitedException()
                }
                StepResult.LoginWall -> wall = true
                StepResult.Gone -> {
                    gone[code] = clock()
                    return FetchResult(bestStep, best)
                }
            }
        }
        // Every step walled and nothing found: try again in 10 min rather than make a note from nothing,
        // but give up after a few runs so the reel isn't stuck in the queue for ever.
        if (wall && bestStep == 0 && walled.merge(code, 1, Int::plus)!! < wallTries) {
            pausedUntil = maxOf(pausedUntil, clock() + wallRetryMs)
            throw RateLimitedException()
        }
        walled.remove(code)
        return FetchResult(bestStep, best)
    }
}
