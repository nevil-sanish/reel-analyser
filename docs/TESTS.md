# Reel Bot: test catalogue

Every test the app must have, by ID. Code doesn't exist yet: all tests are **planned**. When a test is written, set its status to **written** and fill in its file; when it runs in CI or a release check, **passing**. **Update this file in the same commit as the code or doc change it tests** ([RELEASES.md](RELEASES.md) §2). Endpoint IDs refer to [ENDPOINTS.md](ENDPOINTS.md).

## 0. Levels, locations and commands

| Level | What | Where | Run with |
|---|---|---|---|
| **unit** | Pure logic, no Android, no network | Kotlin: `mobile/packages/reelbot_native/android/src/test/kotlin/app/reelbrain/` · Dart: `mobile/test/` | `cd mobile/android && ./gradlew :reelbot_native:testDebugUnitTest` · `cd mobile && flutter test` |
| **fixture** | Parsers fed saved real responses | Fixtures in `mobile/packages/reelbot_native/android/src/test/resources/ig/` | same as unit |
| **integration** | Several parts with fakes for the network | `mobile/test/` (Dart), Robolectric for Kotlin (`CounterPluginTest.kt`) | same as unit |
| **live** | Real calls to Instagram/YouTube/Gemini from a phone | Debug screen → "Run live checks" (no CI: needs a residential IP and keys) | manually, weekly and before each release |
| **manual** | Steps a person does on a phone | this file | before each release; results go in the release notes |

Fixture rules:
- Save fixtures from a **logged-out** browser or the app's own WebView; strip cookies and tokens.
- Name: `{endpoint}-{case}-{yyyymmdd}.html|json`, e.g. `ig-embed-video-20261105.html`.
- The v0.1.0 fixtures are `*-synthetic.*`: hand-built from the shapes in ENDPOINTS.md, not captured. Add a real capture beside each one at the first live check; keep both passing.
- When a live test fails, save the new response as a fixture first, then fix the parser until both old and new fixtures pass.

Status values: **planned** · **written** · **passing** · **retired** (keep the row, say why).

---

## 1. Instagram fetcher (Phase 1)

| ID | Level | Covers | Given → Expect | Status |
|---|---|---|---|---|
| T-IG-U01 | unit | shortcode → `mediaId` | Known pairs (from yt-dlp's test cases) decode correctly; invalid character → error | passing |
| T-IG-U02 | unit | URL parsing | `/reel/`, `/reels/`, `/p/`, `/tv/`, with `?igsh=` and trailing text → same `code` | passing |
| T-IG-U03 | unit | IG-CDN | `oe=` hex expiry parsed; expired URL not downloaded; > 100 MB stops | passing |
| T-IG-U04 | unit | cascade order | Fake steps: step 1 returns video → steps 2–6 not called; steps 1–4 empty, 5 metadata → result has caption, no video, `step = 5` | passing |
| T-IG-U05 | unit | rate limits | Two fetches 1 s apart → second waits ≥ 5 s; a 429 → no `IG-*` call for 30 min | passing |
| T-IG-U06 | unit | negative cache | Private post → same `code` not fetched again within 1 h; other codes still fetched | passing |
| T-IG-U08 | unit | IgCascade | A login wall skips only its step (the next step's video wins, no pause); all steps walled → retry after 10 min, give up on the 3rd run; 429 still pauses 30 min | passing |
| T-IG-U07 | unit | single-flight | Two concurrent fetches of one `code` → one network fetch, both get the result | passing |
| T-IG-F01 | fixture | IG-EMBED | Embed page with `contextJSON` + `video_url` → video URL, caption, author | passing |
| T-IG-F02 | fixture | IG-EMBED | Embed page with `gql_data: null` → "no data", cascade continues | passing |
| T-IG-F03 | fixture | IG-POST-PAGE | `data-sjs` scripts with `if_not_gated_logged_out` → item found by `pk`; ≥ 480 px rendition chosen | passing |
| T-IG-F04 | fixture | IG-POST-PAGE | Login-wall page (still has og: tags) → `loginWall` read from the `/accounts/login` path; `require_login` GraphQL → login wall. What the wall does to the cascade is T-IG-U08 (v0.9.1: skips only that step) | passing (synthetic) |
| T-IG-F05 | fixture | IG-GQL-LOGGEDOUT | Response with `xig_polaris_media.if_not_gated_logged_out` → video URL | passing |
| T-IG-F06 | fixture | IG-GQL-LOGGEDOUT | Response without `data` → "stale query" → IG-JS-BUNDLE called once | passing |
| T-IG-F07 | fixture | IG-GQL-WEB | Response with `xdt_shortcode_media.video_url` → video URL; null → next step | passing |
| T-IG-F08 | fixture | IG-OEMBED | oEmbed JSON → title, author, thumbnail | passing |
| T-IG-F09 | fixture | IG-JS-BUNDLE | Saved bundle → `docId` for both query names; missing → keeps bundled id | passing |
| T-IG-F10 | fixture | carousels | Carousel in each format (embed, page, GraphQL) → first video, else images | passing |
| T-IG-F13 | fixture | IG parsers | Carousel and single posts list their stills in order, carousel videos skipped; `fill` keeps images | passing |
| T-IG-F12 | fixture | IG-EMBED-PLAYER | Range params stripped from a CDN .mp4; blob src → intercepted mp4; caption loses the username and "View all" tail | passing |
| T-IG-F11 | fixture | IG-POST-PAGE | Rendered page: `<video>` src (not blob:) or `"video_url"` in HTML, plus og:image / og:description → video, thumbnail, author, caption | passing |

## 2. Pipeline and analysis (Phase 1)

| ID | Level | Covers | Given → Expect | Status |
|---|---|---|---|---|
| T-PIPE-01 | integration | GEM-GENERATE (YouTube) | Shorts URL → `fileData.fileUri` request; status `done` | passing |
| T-PIPE-02 | integration | YT-OEMBED | Gemini rejects the URL → oEmbed used → status `caption+thumbnail` | passing |
| T-PIPE-03 | integration | GEM-GENERATE (Instagram video) | `fetchInstagram` returns `videoPath` ≤ 20 MB → `inlineData`; status `done`; `step` stored; video file deleted | passing |
| T-PIPE-04 | integration | caption+thumbnail | `fetchInstagram` returns caption + thumbnail only → status `caption+thumbnail` | passing |
| T-PIPE-05 | integration | APIFY-RUN | Apify key set and steps 1–5 give no video → Apify called with `Authorization: Bearer`; key never in the URL | passing |
| T-PIPE-06 | integration | GEM-GENERATE errors | 429 or 5xx → item stays `queued`; 400 → next thinking level, then next model | passing |
| T-PIPE-07 | integration | GEM-UPLOAD | Video > 20 MB → resumable upload, poll until `ACTIVE`, generate, then `DELETE` | passing |
| T-PIPE-08 | integration | no key | No Gemini key → item stays `queued`; library shows the "Add your Gemini key" banner | passing |
| T-PIPE-09 | integration | nothing found | `fetchInstagram` empty and nothing captured → status `failed` | passing |
| T-PIPE-11 | integration | GEM-GENERATE | Two Gemini keys, two reels → one reel per key; a 429 on key 1 moves that reel to key 2 | passing |
| T-PIPE-12 | integration | OPENAI-CHAT | No Gemini key, OpenAI key, Instagram video → 6 frames sent as images; fenced JSON reply parsed | passing |
| T-UI-01 | widget | intro | Next ×2 reaches *Slide to unlock*; a short drag springs back; a full drag unlocks once with a heavy haptic (`test/intro_test.dart`) | passing |
| T-LIB-01 | integration | library DB | Seen notes saved > 3 days ago archive; unseen stay; `reels()` without a filter still sees all; restore works | passing |
| T-PIPE-13 | integration | runner | A re-queued text-only Instagram item with its note removed is analysed again, now from video | passing |
| T-UI-02 | unit | saved label | just now / 30m ago / 12h ago / yesterday / 3 Nov / 31 Dec 2025; full "Saved 6 Nov 2026, 09:05" | passing |
| T-PIPE-14 | integration | photos | A shared photo goes to Gemini as an image ("not a video") and is saved with app `photo` | passing |
| T-PIPE-15 | integration | posts | An Instagram post with 3 images and no video sends all 3 in one request → `done` | passing |
| T-LIB-02 | integration | chats | Saved chats: create, update, newest first, delete | passing |
| T-UI-03 | unit | Insights | Missing days filled with zeros; weekday averages; hour labels | passing |
| T-UI-04 | unit | Library kinds | Instagram /reel/ → reel, /p/ → post, YouTube → short, shared picture → photo | passing |
| T-UI-05 | widget | FadingTabs | After switching tabs, the left tab's rendered opacity is 0 and the new one's 1 | passing |
| T-UI-06 | widget | multi-select | Long-press calls select; a selected card shows a tick, an unselected one an empty circle | passing |
| T-USE-01 | unit | AppUsage | Sessions end when the app's last screen pauses, at screen off, or now; overlays inside the app (a modal over the main screen) keep one session; other apps and repeated resumes ignored (`AppUsageTest.kt`). Matches `dumpsys usagestats` on a phone | passing |
| T-USE-02 | unit | AppUsage | A session over midnight and an hour boundary is split by local date and hour | passing |
| T-USE-03 | integration | CH-COUNTER | Usage-access time joins the counter's days (counts kept, time replaced) and replaces the hourly time; without it the counter's time stays | passing |
| T-UI-07 | widget | Reduce effects | On: no `BackdropFilter` and no running animation; off again: both back (`test/reduce_effects_test.dart`) | passing |
| T-LIB-03 | integration | library search | A word found only in the overview or mentions finds the note | passing |
| T-PIPE-10 | integration | lock | App and background runner start together → each item analysed once | passing |
| T-EXP-01 | integration | Export/Import | Export → wipe → Import → same notes and chats; Import twice → no duplicates (notes by URL, chats by first question + time); a v1 file imports | passing |

## 3. Share, channel, background (Phase 1)

| ID | Level | Covers | Given → Expect | Status |
|---|---|---|---|---|
| T-SHARE-01 | unit | SHARE-IN | Instagram share text with words around the URL → URL extracted, `igsh` stripped | passing |
| T-SHARE-02 | unit | SHARE-IN | `youtube.com/shorts/{id}?si=…` and `youtu.be/{id}` → canonical Shorts URL | passing |
| T-SHARE-03 | unit | SHARE-IN | Non-reel text → "Not a reel link", no row | passing |
| T-SHARE-04 | unit | SHARE-IN | URL-less row < 2 min old (bubble Save; 10 s before v0.5.0) → URL attached to it; older → new row | removed (v0.9.0: no bubble) |
| T-CH-01 | integration | CH-COUNTER | `pendingItems` / `setPendingStatus` round-trip through a real `MethodChannel` and `counter.db` (Robolectric, `CounterPluginTest.kt`); Dart side maps rows and sends id, status, title | passing |
| T-CH-02 | integration | CH-COUNTER | `fetchInstagram` maps Kotlin result to Dart types; `rate_limited` → `RateLimited`, other errors stay `PlatformException`; on the Kotlin side an exception off the main thread replies `failed` | passing |
| T-BG-01 | integration | WM-ANALYSE | The task body (`analyseAndNotify`) processes the queue with fakes and posts one "N notes ready"; nothing queued → no notification. Opening the real stores in a background engine still needs a phone (T-BG-02) | passing |
| T-BG-02 | manual | WM-ANALYSE | Share 3 reels, keep the app closed 30 min → all analysed | planned |

## 4. Counter (Phase 2)

| ID | Level | Covers | Given → Expect | Status |
|---|---|---|---|---|
| T-TRK-01 | unit | ReelTracker | 20 reels × 3 s → count 20 | passing |
| T-TRK-02 | unit | ReelTracker | Half-swipe (0.5 s) + swipe back + 0.75 s refresh flicker → count 1 | passing |
| T-TRK-03 | unit | ReelTracker | Swipe back, rewatch later the same day → each reel once | passing |
| T-TRK-04 | unit | ReelTracker | 2 s on one reel → counted while still on it | passing |
| T-TRK-05 | unit | ReelTracker | Nothing readable for 3 s → 0 reels, 1 unknown | passing |
| T-TRK-06 | unit | ReelTracker | 4 s on a reel → dwell ≈ 4 s | passing |
| T-TRK-07 | unit | ReelTracker | 10 s, 60 s gap (asleep), 10 s → screen time ≈ 20 s | passing |
| T-TRK-08 | unit | ReelTracker | Leave Reels for the feed → session ends | passing |
| T-TRK-09 | unit | ReelTracker | Same reel on IG and YT → counted separately | passing |
| T-FP-01 | unit | Fingerprint | Truncated "… more" vs expanded caption → same id | passing |
| T-FP-02 | unit | Fingerprint | `normalize` strips "… more" / "...more" / "less", lowercases | passing |
| T-FP-03 | unit | Fingerprint | Blank item → null | passing |
| T-FP-04 | unit | Fingerprint | Different author or app → different id | passing |
| T-FP-05 | unit | Fingerprint | Same author, no caption/audio/title, likes `12K` vs `340` → two reels | passing |
| T-FP-06 | unit | Fingerprint | Caption-less reel, likes `12.3K` → `12.4K` mid-watch → one reel | passing |
| T-FP-07 | unit | Fingerprint | Reel with caption, likes change → one reel | passing |
| T-FP-08 | unit | Fingerprint | `likeBucket`: `523`→`520`, `12.3K`→`12000`, `1.2M`→`1200000`, junk→`""` | passing |
| T-RULE-01 | unit | DetectionRules | Not on Reels screen → `inReels = false` | passing |
| T-RULE-02 | unit | DetectionRules | Known ids → author, caption, likes read | passing |
| T-RULE-03 | unit | DetectionRules | Fallback: bottom-half text used; `12.3K`, `Subscribe` skipped | passing |
| T-RULE-04 | unit | DetectionRules | Mid-swipe: page covering the centre wins | passing |
| T-RULE-05 | unit | DetectionRules | Invisible nodes ignored | passing |
| T-RULE-06 | fixture | DetectionRules | Captured `tree_instagram` / `tree_youtube` dumps from a real phone → expected `Observation` | planned |
| T-ALERT-01 | unit | unknown alert | Fires at 5 unknown and ≥ 30%; not at 4; not twice a day | passing |
| T-CH-03 | integration | CH-COUNTER | `daily`, `seenItems`, `debugState`, `setCapture` | passing (Dart side; Kotlin side needs a device) |
| T-CH-04 | integration | CH-COUNTER | `status` fields on API 29, 33, 35 | planned |

## 5. Bubble, auto-Save, digest, releases (Phases 3–4)

| ID | Level | Covers | Given → Expect | Status |
|---|---|---|---|---|
| T-SAVE-01 | manual | bubble Save | Tap Save → row with on-screen text; Share → Reel Bot attaches the URL | removed (v0.9.0: no bubble) |
| T-SAVE-02 | manual | SaveAutomator | 30 automated Saves (15 IG, 15 YT) on 2 phones → success rate; < 90% → delete auto-Save | removed (v0.9.0: no bubble) |
| T-SAVE-03 | unit | SaveAutomator | Share button found by id, then by description; sheet finds "Reel Bot", else "Share to…" / "More"; invisible nodes skipped | removed (v0.9.0: no bubble) |
| T-DIG-01 | integration | WM-DIGEST | App not opened today, 2 analysed items → notification with titles | passing (unit: rule and text; worker needs a device) |
| T-DIG-02 | integration | WM-DIGEST | Nothing analysed → counts only; app opened today → no notification | passing (unit: rule and text; worker needs a device) |
| T-REL-01 | unit | GH-RELEASE-LATEST | Newer `tag_name` → update banner with the `.apk` asset; same/older → nothing; 403 → silent | passing (v0.9.4) |

## 6. Live checks (debug screen, weekly and before each release)

Run from the phone, logged out, with a fixed set of public test URLs kept in `mobile/assets/live_urls.json` (3 Instagram reels, 1 carousel, 1 photo post, 1 private post, 2 Shorts, 1 unlisted video). Record results in the release notes.

| ID | Covers | Expect | Status |
|---|---|---|---|
| T-LIVE-01 | IG-EMBED | Returns metadata for all public posts; note which give a video | planned |
| T-LIVE-02 | IG-POST-PAGE | Video for ≥ 2 of 3 reels | planned |
| T-LIVE-03 | IG-GQL-LOGGEDOUT | Video for ≥ 2 of 3 reels; no stale-query error | planned |
| T-LIVE-04 | IG-GQL-WEB | Video for ≥ 2 of 3 reels; no stale-query error | planned |
| T-LIVE-05 | IG-OEMBED | Title + thumbnail for all public posts | planned |
| T-LIVE-06 | IG-CDN | Downloaded file plays; size < 100 MB | planned |
| T-LIVE-07 | APIFY-RUN | (only with a key) video for all reels | planned |
| T-LIVE-08 | GEM-GENERATE | Summary for both Shorts | planned |
| T-LIVE-09 | YT-OEMBED | Unlisted video → oEmbed result or clear `failed` | planned |
| T-LIVE-10 | whole cascade | **≥ 80% of public reels get a video without Apify** (Phase 1 exit bar) | planned |

## 7. Manual release checks

| ID | Steps | Expect | Status |
|---|---|---|---|
| T-MAN-01 | Fresh install from the GitHub release APK on Android 13+ | Installs (note any Play Protect prompt) | planned |
| T-MAN-02 | Share 10 reels + 10 Shorts with the app closed | All summarised within 30 min (Phase 1 exit test) | planned |
| T-MAN-03 | Sloppy-use counter test: 20 reels + 20 Shorts with 5 swipe-backs, 3 half-swipes, 1 refresh, 2 rewatches, 3 caption-less reels from one creator | Count within ±1 (Phase 2 exit test) | planned |
| T-MAN-04 | Setup checklist on a Xiaomi/Realme and a stock phone | Every button opens the right screen | passing on Nothing A059 (Android 16); Xiaomi/Realme still planned |
| T-MAN-05 | Reboot, kill the app | Counting and background analysis resume | kill passing (Nothing A059); reboot planned |
| T-MAN-06 | Rename one detection id on purpose | Unknown alert fires | planned |
| T-MAN-07 | After 21:00, run the digest: `adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler app.reelbrain <id>` once its hourly window is up (WorkManager delays earlier forced runs; before 21:00 the worker posts nothing by design) | Notification as in T-DIG-01/02 | planned |

## 8. Change log

| Date | Change |
|---|---|
| 2026-11-05 | First version: all tests planned, mapped to [ENDPOINTS.md](ENDPOINTS.md) and [PLAN.md](PLAN.md) phases. |
| 2026-11-05 | v0.1.0: Phase 1 unit, fixture and integration tests written and passing (synthetic IG fixtures). T-IG-F04, T-CH-*, T-BG-*, live and manual checks still planned. |
| 2026-11-05 | v0.1.1: T-PIPE-06 and the Instagram rate-limit test also check the reason shown in the library. |
| 2026-11-06 | v0.2.0: T-TRK-*, T-FP-*, T-RULE-01…05 and T-ALERT-01 written and passing (Kotlin unit); T-CH-03 passing on the Dart side. T-RULE-06 needs captured trees; T-CH-04 and T-MAN-03…06 need a phone. |
| 2026-11-06 | v0.3.0: T-SAVE-03 (unit) added and passing. T-SAVE-01/02 need a phone. |
| 2026-11-06 | v0.9.5, Usage access: T-USE-01…03 added and passing. |
| 2026-11-06 | On the phone (Nothing A059, Android 16): T-MAN-04 passes on this brand after the Accessibility-check fix; T-MAN-05 kill part passes (reboot still to do); first T-LIVE run 5 of 5 from video. The rate-limit test also checks the login-wall message. |
| 2026-11-06 | v0.9.5: T-IG-F04, T-CH-01, T-CH-02, T-BG-01 and T-UI-07 added and passing; the Kotlin channel tests run on Robolectric. |
| 2026-11-06 | v0.9.4: T-REL-01 added and passing; T-EXP-01 covers chats. Sharing several photos needs a phone. |
| 2026-11-06 | v0.9.3: T-LIB-03 added and passing. Re-analyse-all and the photo sweep aren't unit-tested (they need the plugin); check them on a phone. |
| 2026-11-06 | v0.9.2: T-PIPE-01 checks overview and mentions are requested and saved; T-UI-03 checks the time-of-day blocks. |
| 2026-11-06 | v0.9.1: T-IG-U08 added and passing; the 30-min pause test now uses a 429. |
| 2026-11-06 | v0.9.0: bubble and auto-Save removed, so T-SAVE-01…03 and T-SHARE-04 are retired; T-UI-06 added and passing. |
| 2026-11-06 | v0.8.2: T-UI-05 added and passing (regression test for overlapping tabs). |
| 2026-11-06 | v0.8.1: T-LIB-02, T-UI-03 and T-UI-04 added and passing. |
| 2026-11-06 | v0.8.0: T-PIPE-14, T-PIPE-15 and T-IG-F13 added and passing. |
| 2026-11-06 | v0.7.0: UI-only release; all existing tests pass unchanged. |
| 2026-11-06 | v0.6.2: T-IG-F12, T-PIPE-13 and T-UI-02 added and passing; the Apify test expects step 7. |
| 2026-11-06 | v0.6.1: T-UI-01 also checks the unlock haptic. |
| 2026-11-06 | v0.6.0: T-UI-01 and T-LIB-01 added and passing; T-PIPE-01 checks the note-ready titles; T-DIG-02 checks the empty-day nudge. |
| 2026-11-06 | v0.5.0: T-PIPE-11/12 and T-IG-F11 added and passing; T-PIPE-01 also checks the watch URL, fps 0.5 and minimal thinking; T-SHARE-04 now 2 min. |
| 2026-11-06 | v0.4.0: T-DIG-01/02 passing as unit tests of the post rule and text (`DigestTest.kt`); T-PIPE-01 also checks the title passed to Kotlin. |
