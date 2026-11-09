package app.reelbrain

import app.reelbrain.AppUsage.Event
import app.reelbrain.AppUsage.PAUSED
import app.reelbrain.AppUsage.RESUMED
import app.reelbrain.AppUsage.SCREEN_OFF
import app.reelbrain.AppUsage.Session
import java.time.ZoneId
import java.time.ZonedDateTime
import org.junit.Assert.assertEquals
import org.junit.Test

class AppUsageTest {
    private val ig = "com.instagram.android"
    private val yt = "com.google.android.youtube"
    private val zone = ZoneId.of("Asia/Kolkata")
    private fun at(h: Int, m: Int, day: Int = 6) = ZonedDateTime.of(2026, 11, day, h, m, 0, 0, zone).toInstant().toEpochMilli()

    private val main = "com.instagram.mainactivity.InstagramMainActivity"
    private val modal = "com.instagram.modal.ModalActivity"

    // T-USE-01
    @Test fun sessionsEndOnLastPauseScreenOffAndNow() {
        val s = AppUsage.sessions(listOf(
            Event(ig, RESUMED, at(9, 0), main), Event(ig, PAUSED, at(9, 10), main),
            Event(yt, RESUMED, at(11, 0), "Watch"), Event("android", SCREEN_OFF, at(11, 20)), Event(yt, PAUSED, at(11, 21), "Watch"),
            Event(ig, RESUMED, at(12, 0), main), // still open
        ), now = at(12, 7))
        assertEquals(listOf(
            Session("instagram", at(9, 0), at(9, 10)),
            Session("youtube", at(11, 0), at(11, 20)),
            Session("instagram", at(12, 0), at(12, 7)),
        ), s)
    }

    // The bug the phone check found: a modal opening over Instagram's main screen cut the session short.
    @Test fun overlaysInsideTheAppKeepOneSession() {
        val s = AppUsage.sessions(listOf(
            Event(ig, RESUMED, at(9, 0), main),
            Event(ig, RESUMED, at(9, 5), modal), Event(ig, PAUSED, at(9, 5), main),
            Event(ig, RESUMED, at(9, 8), main), Event(ig, PAUSED, at(9, 8), modal),
            Event(ig, PAUSED, at(9, 20), main),
        ), now = at(10, 0))
        assertEquals(listOf(Session("instagram", at(9, 0), at(9, 20))), s)
    }

    @Test fun otherAppsAreIgnoredAndRepeatedResumesDoNotRestart() {
        val s = AppUsage.sessions(listOf(
            Event("com.whatsapp", RESUMED, at(8, 0), "W"), Event("com.whatsapp", PAUSED, at(8, 30), "W"),
            Event(ig, RESUMED, at(9, 0), main), Event(ig, RESUMED, at(9, 5), main), Event(ig, PAUSED, at(9, 20), main),
        ), now = at(10, 0))
        assertEquals(listOf(Session("instagram", at(9, 0), at(9, 20))), s)
    }

    // T-USE-02
    @Test fun splitAtHourAndMidnight() {
        val (daily, hourly) = AppUsage.split(listOf(Session("instagram", at(23, 50, day = 5), at(0, 15))), zone)
        assertEquals(mapOf(("2026-11-05" to "instagram") to 600_000L, ("2026-11-06" to "instagram") to 900_000L), daily)
        assertEquals(mapOf((23 to "instagram") to 600_000L, (0 to "instagram") to 900_000L), hourly)
    }
}
