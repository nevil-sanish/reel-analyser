# Reel Bot: implementation guide (file by file)

How to build what [PLAN.md](PLAN.md) describes. Network calls: [ENDPOINTS.md](ENDPOINTS.md). Tests: [TESTS.md](TESTS.md). **Phases 1 and 2 are specified in full.** Phases 3–4 list the files and their behaviour.

---

## 0. Setup

### 0.1 Built from scratch

The old app (commit `5f0c001`) isn't in this repository's history, so v0.1.0 was written fresh with `flutter create`. §1 below describes the old app's cleanup and is kept for reference only; the new code never had the server parts.

**Layout:** all Kotlin lives in a local Flutter plugin, `mobile/packages/reelbot_native` (Kotlin package `app.reelbrain`, Android namespace `app.reelbrain.core`), added to `pubspec.yaml` as a path dependency. A channel set up in `MainActivity.configureFlutterEngine` would exist only in the UI engine. The background engine that `workmanager` starts registers only the plugins listed in `GeneratedPluginRegistrant`, so `reelbot/counter` has to be a pubspec plugin to reach `pending_items` from the background task. Kotlin paths below read `mobile/packages/reelbot_native/android/src/main/kotlin/app/reelbrain/`.

### 0.2 Root `.gitignore`

```
mobile/.dart_tool/
mobile/build/
mobile/.flutter-plugins
mobile/.flutter-plugins-dependencies
mobile/android/.gradle/
mobile/android/.kotlin/
mobile/android/local.properties
mobile/android/key.properties
mobile/android/app/release/
mobile/android/gradlew
mobile/android/gradlew.bat
mobile/android/gradle/wrapper/gradle-wrapper.jar
mobile/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java
*.jks
*.keystore
.env
```

### 0.3 Toolchain

- **Flutter:** stable 3.47.x (Dart 3.13.x). `pubspec.yaml` needs `sdk: ^3.13.5`.
- **Android SDK:** platform 36 and build-tools 36.
- **Gradle:** the wrapper uses Gradle 9.3.1; AGP 9.1.0 and Kotlin 2.4.0 are set in `settings.gradle.kts`.

---

## 1. Remove the server parts (Phase 1)

The old app had sign-in, credits, Play billing and a server. All of that goes.

### 1.1 Delete these files

| File | Why |
|---|---|
| `mobile/lib/data/api_client.dart` | Server API |
| `mobile/lib/data/billing.dart` | Play billing |
| `mobile/lib/data/session.dart` | Google sign-in / session |
| `mobile/lib/core/config.dart` | Server URL and client ids |
| `mobile/lib/ui/plans_screen.dart` | Paid plans |
| `mobile/lib/ui/sign_in_screen.dart` | Sign-in |
| `mobile/lib/ui/link_screen.dart` | Instagram linking |
| `mobile/lib/ui/account_screen.dart` | Account |

### 1.2 `pubspec.yaml`

- Remove `google_sign_in` and `in_app_purchase`.
- Add `workmanager` (background analysis, §2.4).
- Set the description to "Reel Bot: turns the reels you share into searchable notes, and counts the Reels and Shorts you watch."

### 1.3 Edit these files

| File | Change |
|---|---|
| `lib/core/models.dart` | Delete `Account` and `PlanInfo`. Remove `serverJobId` from `Job`. |
| `lib/data/library_db.dart` | Drop the `server_job_id` and `pending_upload` columns and their methods (`pendingUploads`, `setServerJob`, `clearAll`). `saveReel(reel, {savedAt})` only. |
| `lib/data/key_store.dart` | Keep `gemini` and `groq`; add optional `apify`. |
| `lib/pipeline/runner.dart` | Own-key only. Delete `_runOnServer`, `_serverFetch`, `_share`, `uploadPending`, `sync`, `_download` and the `api`/`allowServerFetch`/`http` fields. In `run()`, if there's no Gemini key, leave the item `queued` and show "Add your Gemini API key in Settings to analyze reels." |
| `lib/app_services.dart` | No `api`, `session` or `billing`. Add `CounterBridge bridge`. `ask()` uses only the user's key. |
| `lib/ui/home_screen.dart` | Rename to `library_screen.dart` / `LibraryScreen`. Remove sync, account and the credits banner. Show an "Add your Gemini key" banner when there's no key, and a "N waiting to be analysed" line when items are queued. The app bar has *Ask your library* and *Your AI keys*. |
| `lib/ui/settings_screen.dart` | Remove the "server fetch" switch and any credits wording. Add the optional Apify key. |
| `lib/ui/reel_screen.dart` | Remove "Report wrong summary" (it called the server). Show a "Summary from caption + thumbnail" label when `analysis = "caption+thumbnail"`. |
| `lib/main.dart` | No sign-in. Phase 1 root is `LibraryScreen`; Phase 2 makes it a `NavigationBar` with **Today** and **Library**. App title "Reel Bot". |

---

## 2. Share → summary (Phase 1)

Kotlin files go in `mobile/packages/reelbot_native/android/src/main/kotlin/app/reelbrain/` (see §0.1). The application id is `app.reelbrain`.

### 2.1 `CounterDb.kt`: `counter.db`, owned by Kotlin

An `SQLiteOpenHelper` singleton (`CounterDb.get(context)`), WAL enabled in `onConfigure`. Phase 1 creates only `pending_items`; Phase 2 adds the counter tables (§3.3) in a version bump.

```sql
CREATE TABLE pending_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  url TEXT, app TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
  on_screen_text TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued');  -- queued | done | caption+thumbnail | text-only | failed
```

**Dart never opens this file** (see PLAN §4.7).

### 2.2 `ShareReceiverActivity.kt`

A transparent activity (no Flutter) for `ACTION_SEND` `text/plain`.
1. Extract the first `instagram.com/(reel|reels|p|tv)/…` or `youtube.com/shorts/…` / `youtu.be/…` URL. None → toast "Not a reel link", `finish()`.
2. If the newest `pending_items` row has no URL and is under 2 min old (a bubble Save from Phase 3; 10 s before v0.5.0, which was too short to share by hand), fill in its URL; otherwise insert a new row.
3. Toast "Saved ✓" and `finish()`, so you stay in Instagram/YouTube.

*Not in v0.1.0:* `res/xml/shortcuts.xml` + `ShortcutManagerCompat.pushDynamicShortcut` for the Direct Share row. Reel Bot shows in the normal share list; add the shortcut if it's hard to find.

### 2.3 `CounterPlugin.kt`: the `reelbot/counter` channel

A `FlutterPlugin` in the local `reelbot_native` package (§0.1), so it is registered in **every** Flutter engine, including the one `workmanager` starts in the background.

| Method | Returns / does |
|---|---|
| `pendingItems {status}` | `List<Map>` |
| `setPendingStatus {id, status}` | updates one row |
| `fetchInstagram {url}` | runs `InstagramFetcher` (§2.5) and returns `{step, author, caption, thumbnailUrl, videoPath}`; `videoPath` is a downloaded file in the app cache, or null. Error code `rate_limited` while Instagram is paused |
| `saveDownload {name, text}` | writes `Downloads/ReelBot/<name>` through MediaStore (Export, §2.6), replacing an earlier file of the same name |

Phase 2 adds the counter methods (§3.5). Activity-only methods (`openAccessibilitySettings` and the rest) start their intents with `FLAG_ACTIVITY_NEW_TASK` from the application context, so they also work without an activity.

### 2.4 Background analysis: `lib/pipeline/background.dart`

- `callbackDispatcher()` (annotated `@pragma('vm:entry-point')`) initialises the key store and library DB, then calls `Runner.processQueue()`.
- `main()` calls `Workmanager().initialize(callbackDispatcher)` and `registerPeriodicTask('analyse', 'analyse', frequency: 15 min, constraints: networkType connected, existingWorkPolicy: keep)`.
- `Runner.processQueue()` also runs on app launch and resume. A simple lock row in the library DB (`processing_until` timestamp, 5 min) stops the app and the background task processing the same item twice.

### 2.5 The pipeline: `lib/pipeline/runner.dart`

For each `queued` item, in order:
- **YouTube:** `gemini.dart` sends the URL as `file_data.file_uri`. No download. Status `done`.
  - If Gemini rejects the URL (private/unlisted, or the free 8 h/day cap): `GET https://www.youtube.com/oembed?url=<url>&format=json` (no key) gives title, channel and thumbnail → caption+thumbnail summary, status `caption+thumbnail`.
- **Instagram:** call `fetchInstagram` (Kotlin, below).
  - `videoPath` set → send the video to Gemini (inline if small, otherwise the Files API). Status `done`.
  - No video, but caption or thumbnail → send caption + thumbnail (+ `on_screen_text` if a bubble Save captured it). Status `caption+thumbnail`.
  - Nothing → captured author/caption/on-screen text only, status `text-only`; nothing captured → `failed`.
  - Store the winning `step` on the library item (Phase 2's debug screen will show counts per step).
- Steps 1–5 and the download are Kotlin (`InstagramFetcher.kt`, with the rules in the pure, JVM-tested `IgCascade.kt` and parsers in `IgParse.kt`). Step 6 (Apify) and its download are Dart (`pipeline/apify.dart`, `runner.dart`).
- Delete the video after analysis; only text is kept.
- Network error, Instagram 429/login redirect, or Gemini 429/5xx → leave `queued` for the next run.

#### `InstagramFetcher.kt` (Kotlin)

Why Kotlin + WebView: the logged-out endpoints only answer a real browser (yt-dlp has to fake Chrome's TLS fingerprint with `curl-cffi`). An Android `WebView` *is* Chrome, so it passes without faking anything, keeps Instagram's anonymous cookies (`csrftoken`, `mid`, `ig_did`) in `CookieManager`, and uses an honest user agent.

- One hidden `WebView` (not attached to a window), created and driven on the main thread; `fetch()` suspends until done, 20 s timeout per step. JavaScript on, images off.
- `shortcode` from `instagram.com/(reel|reels|p|tv)/<code>`; `mediaId` = shortcode decoded as base-64 (alphabet `A–Z a–z 0–9 - _`).
- Steps, stopping at the first that yields a video URL (order and reasons: PLAN §3.2; exact requests: [ENDPOINTS.md](ENDPOINTS.md) §2):
  1. `IG-EMBED`: plain HTTPS GET of the embed page, parse `contextJSON`.
  2. `IG-POST-PAGE`: load the post page in the hidden WebView, parse `data-sjs` JSON by `pk == mediaId`. Keep the page loaded.
  3. `IG-GQL-LOGGEDOUT`: same-origin `fetch()` from that page with its LSD token and `csrftoken`.
  4. `IG-GQL-WEB`: same, with the shortcode query.
  5. `IG-OEMBED`: title, author, thumbnail (no video).
  6. `APIFY-RUN`, only if the user has added a key (`pipeline/apify.dart` result passed back in).
  7. Otherwise return caption/author/thumbnail from whichever step found them, with no video.
- Around the steps: single-flight per `code`, 1 h negative cache for private/deleted posts, the rate-limit rules in ENDPOINTS §1.
- **Download in the same call**: OkHttp GET of the chosen CDN URL with `Referer: https://www.instagram.com/` and the WebView's user agent, to `cacheDir/ig/<code>.mp4`; cap at 100 MB.
- **Query ids rot.** `doc_id`s live in `res/raw/ig_queries.json` (not in code), so a fix is a one-line change. On a stale-query error, rediscover the id (`IG-JS-BUNDLE`) and cache it in SharedPreferences.
- Never log in and never send the user's cookies from the Instagram app (the WebView's cookie jar is separate from it).

### 2.6 Export/Import

`Downloads/ReelBot/library.json` plus one `.md` per reel, written by Kotlin's `saveDownload` (MediaStore, so `minSdk` is 29 and no storage permission is needed). Import picks a `library.json` with `file_picker` and merges by URL (`lib/data/export.dart`).

### 2.7 Phase 1 manifest

```xml
<activity android:name=".ShareReceiverActivity" android:exported="true"
    android:theme="@android:style/Theme.Translucent.NoTitleBar"
    android:excludeFromRecents="true" android:taskAffinity="">
  <intent-filter>
    <action android:name="android.intent.action.SEND"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <data android:mimeType="text/plain"/>
  </intent-filter>
  <meta-data android:name="android.service.chooser.chooser_target_service"
      android:value="androidx.sharetarget.ChooserTargetServiceCompat"/>
</activity>
```

---

## 3. Native counter (Phase 2, Kotlin)

### 3.0 Capture first

Before writing `DetectionRules.kt`, ship `ReelCounterService` (§3.4) with a rules stub whose `inReels` is "package is Instagram/YouTube", and the debug screen (§4.3). On your phone, turn on capture, open Reels and Shorts (include a caption-less reel and a reel mid-swipe), and copy `tree_instagram` / `tree_youtube`. Fill the id lists in §3.2 from those trees. The lists below are only starting points.

**v0.2.0 status:** built without a phone, so `DetectionRules.kt` ships the starting-point ids below (likes ids guessed: `like_count`, `clips_like_count`, `likes_count` / `like_button`, `reel_like_button`) plus the fallback. The capture step is still to do: paste the trees, then replace the lists and add the T-RULE-06 fixtures.

### 3.1 `ReelTracker.kt`: pure logic, JVM-testable

**`ItemText(author, caption, audio, title, likes)`** is what could be read for the reel on screen. `likes` is the raw like-count label (`""` if none). `isBlank()` is true when author, caption, audio and title are blank (`likes` alone doesn't identify a reel).

**`Fingerprint`**
- `normalize(s)`:
  1. Collapse whitespace and trim.
  2. Strip a trailing `… more` / `...more` / `more` / `less`, and a trailing ellipsis.
  3. Lowercase.
- `likeBucket(label)`: parse `523`, `12.3K`, `1.2M` (and `,` separators) to a number, keep its **2 leading significant figures** (`523` → `520`, `12.3K` → `12000`). Unparseable → `""`.
- `of(app, item)`:
  - Returns `null` when the item is blank.
  - `extra` = `likeBucket(item.likes)` **only when caption, audio and title are all blank**; otherwise `""`. So reels with a caption keep a stable id while their like count changes.
  - Returns the first 20 hex characters of `sha1(app | norm(author) | norm(caption).take(40) | norm(audio) | norm(title) | extra)`.
  - **40 caption characters**, so the truncated and expanded forms of a caption give the same id.

**`TrackerSink`** is the interface that `CounterDb` implements:

```kotlin
fun commitItem(date: String, app: String, fp: String, firstSeen: Long, item: ItemText) // ignore repeats of (date, app, fp)
fun addDwell(date: String, app: String, fp: String, ms: Long)
fun addScreenTime(date: String, app: String, ms: Long)
fun addUnknown(date: String, app: String)
```

**`ReelTracker(sink, minDwellMs = 1500, maxGapMs = 5000, flushEveryMs = 30000, dateOf = localDate)`**

State: current `app`, `lastSeen`, `lastFlush`, and the current item (`fp`, `item`, `since`, `committed`).

`observe(now, app, inReels, seen)`:
1. If a session is active and `now - lastSeen > maxGapMs`, call `end(lastSeen)`. A sleeping phone isn't counted as watch time.
2. If `app == null` or `!inReels`, call `end(now)` and return.
3. Compute `newFp = Fingerprint.of(app, seen)`.
4. **New app:** `end(now)`, set `app` and `lastFlush = now`, then `start(now, newFp, seen)`.
   **Same app, `newFp != fp`:** `leave(now)`, then `start(now, newFp, seen)`.
5. Set `lastSeen = now`.
6. If `!committed && now - since >= minDwellMs`, call `commit()`. This counts the reel **live**, while you're still on it.
7. If `now - lastFlush >= flushEveryMs`, call `flush(now)`.

The private steps:
- **`commit()`:** `fp == null` → `addUnknown`; otherwise → `commitItem`. Then `committed = true`.
- **`leave(now)`:** if committed and `fp != null`, call `addDwell(now - since)`.
- **`flush(now)`:** `addScreenTime(now - lastFlush)`, then `lastFlush = now`.
- **`end(now)`:** let `at = max(now, lastFlush)`. Commit if the dwell rule is met, then `leave(at)` and `flush(at)`, and reset all state.

`active` is `app != null`. `current` is `(fp, item)`, for the debug screen.

### 3.2 `DetectionRules.kt`: everything that depends on Instagram/YouTube layouts

**Plain data types** (no Android types, so the rules are unit-testable):
- `Box(left, top, right, bottom)`
- `NodeSnap(id, cls, text, desc, bounds, visible)`. `id` is the resource id after `:id/`; `label` is the text, or else the description.
- `Observation(inReels, item)`

**Packages**
- `com.instagram.android` → `"instagram"`
- `com.google.android.youtube` → `"youtube"`
- **Ignored** (they briefly cover a reel without you leaving it): `com.android.systemui`, `app.reelbrain`, and common keyboards (`com.google.android.inputmethod.latin`, `com.samsung.android.honeyboard`, `com.touchtype.swiftkey`).

**Per-app id lists.** [Guessing] Starting points only; **replace them with the ids from the capture (§3.0)**.

| | Instagram | YouTube |
|---|---|---|
| screen (any present → on Reels/Shorts) | `clips_viewer_view_pager`, `clips_viewer_root`, `clips_viewer_root_layout`, `clips_video_container`, `clips_swipe_refresh_container`, `clips_tab` | `reel_recycler`, `reel_player_page_container`, `reel_watch_player`, `reel_watch_fragment_root`, `shorts_container` |
| page | `clips_viewer_page`, `clips_item_container`, `clips_media_component`, `clips_video_container` | `reel_player_page_container`, `reel_watch_player` |
| author | `clips_author_username`, `clips_author_info_component`, `row_feed_photo_profile_name`, `username` | `reel_channel_name`, `channel_name`, `reel_channel_bar_inner_container` |
| caption | `clips_caption_component`, `clips_caption`, `clips_caption_text`, `caption_text` | — |
| audio | `clips_audio_attribution`, `clips_music_attribution`, `audio_attribution`, `music_attribution_text` | `reel_sound_metadata`, `reel_music_metadata` |
| title | — | `reel_multi_format_title`, `reel_title`, `shorts_video_title` |
| likes | the like button's count label (id from capture) | the like button's count label (id from capture) |

**Noise labels** (never part of author/caption/audio/title): like, comment, share, send, save, remix, follow, subscribe, more/less, tab names, "original audio", pure counts such as `12.3K`, and ages such as `3d`. The `likes` field is read **only** from the likes ids, never from noise.

**`read(app, nodes, screen)`**
1. `inReels` = any node's id is in the app's screen ids. If not, return `Observation(false, null)`.
2. Keep visible nodes that intersect the screen.
3. **Mid-swipe:** if a page node is at least half the screen tall and contains the screen's vertical centre, keep only nodes inside it.
4. Fill the author, caption, audio, title and likes from the first matching id with a non-noise label (for likes: a parseable count).
5. If the author, caption and title are all blank, use **`fallbackItem`**:
   - Take the non-noise labels in the bottom half of the screen, sorted top to bottom.
   - The author is the first one that starts with `@` or matches `^[\w.]{2,30}$`.
   - The rest are joined as the caption.

### 3.3 `CounterDb.kt`: counter tables

Added to `counter.db` in a version bump; `CounterDb` now implements `TrackerSink`.

```sql
CREATE TABLE seen_items (
  date TEXT NOT NULL, app TEXT NOT NULL, fp TEXT NOT NULL,
  first_seen INTEGER NOT NULL, dwell_ms INTEGER NOT NULL DEFAULT 0,
  author TEXT NOT NULL DEFAULT '', caption TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (date, app, fp));
CREATE TABLE screen_time   (date TEXT NOT NULL, app TEXT NOT NULL, ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (date, app));
CREATE TABLE unknown_items (date TEXT NOT NULL, app TEXT NOT NULL, n  INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (date, app));
CREATE TABLE debug_state   (k TEXT PRIMARY KEY, v TEXT NOT NULL, ts INTEGER NOT NULL);
CREATE VIEW daily_counts AS
  SELECT d.date, d.app,
    (SELECT COUNT(*) FROM seen_items s WHERE s.date = d.date AND s.app = d.app) AS reels,
    COALESCE((SELECT ms FROM screen_time t WHERE t.date = d.date AND t.app = d.app), 0) AS ms,
    COALESCE((SELECT n FROM unknown_items u WHERE u.date = d.date AND u.app = d.app), 0) AS unknown
  FROM (SELECT date, app FROM seen_items UNION SELECT date, app FROM screen_time
        UNION SELECT date, app FROM unknown_items) d;
```

**Writes**
- `commitItem`: `INSERT … ON CONFLICT IGNORE`. A rewatch doesn't add a row.
- v0.5.0: `commitItem` stores only `fp` and times; `author` / `caption` stay empty (version 4 blanks rows from earlier versions). Watched reels are counted, never recorded. Turning capture off deletes `debug_state` `now` and `tree_*`.
- `addDwell`: `UPDATE … dwell_ms = dwell_ms + ?`.
- Counters (`addScreenTime`, `addUnknown`): `INSERT OR IGNORE`, then `UPDATE +?`. UPSERT needs Android 11, so it isn't used.

**Reads (for Flutter)**
- `daily(days)`: `daily_counts` rows from the last `days` days, newest first.
- `seenItems(date)`: that day's rows, newest first.
- `debugState()`: all `debug_state` rows.

### 3.4 `ReelCounterService.kt`: the `AccessibilityService`

**Lifecycle**
- `onServiceConnected`: create the DB and the tracker, register an `ACTION_SCREEN_OFF` receiver that calls `tracker.end(now)`, and set `running = true`.
- `onUnbind`: end the tracker, remove callbacks, unregister the receiver, and set `running = false`.

**`onAccessibilityEvent`**
1. Drop events from ignored packages.
2. Drop events from other apps while nothing is being tracked.
3. Call `evaluate()` at most every **250 ms**.
4. Make sure the **1 s tick** is running while `tracker.active`. The tick keeps dwell, leaving and screen time accurate while a video plays with no events.

**`evaluate()`**
1. `root = rootInActiveWindow`. If its package is ignored, return (neither leaving nor watching).
2. If the package isn't Instagram or YouTube, call `tracker.observe(now, null, false, null)`.
3. Otherwise:
   1. `NodeCollector.collect(root)`: at most 1,500 nodes, depth 40.
   2. `DetectionRules.read(app, nodes, screenBox)`.
   3. `tracker.observe(...)`.
4. If debug capture is on:
   - always write `debug_state["now"]` (app, inReels, fp, author, caption, audio, title, likes);
   - every 3 s, write `debug_state["tree_<app>"]` (up to 400 lines of `V/- id Class [l,t,r,b] label`).

**Unknown alert**
- After each `addUnknown`, read today's totals for that app. If `unknown ≥ 5` and `unknown ≥ 30%` of `reels + unknown`, and no alert was posted today (`debug_state["alerted_<date>"]`), post a notification: "Reel Bot can't read Instagram/YouTube any more. An app update probably changed the screen. Open the debug screen." Tapping it opens the app (v0.2.0: the plugin can't route to a screen, so the Today screen's warning card links to the debug screen).
- Needs `POST_NOTIFICATIONS` (asked for in the setup checklist).

**Rules**
- **Read-only in Phase 2:** no `performAction` and no gestures.
- Debug capture is a SharedPreferences flag (`reelbot` / `debug_capture`), set from Flutter.

### 3.5 Counter methods on `CounterPlugin`

| Method | Returns / does |
|---|---|
| `daily {days}` | `List<Map>` from `CounterDb.daily` |
| `seenItems {date}` | `List<Map>` |
| `debugState` | `List<Map>` |
| `setCapture {on}` | sets the debug flag |
| `status` | `{serviceEnabled, serviceRunning, batteryExempt, notificationsAllowed, sdkInt, manufacturer, capture}` |
| `openAccessibilitySettings` | `Settings.ACTION_ACCESSIBILITY_SETTINGS` |
| `openNotificationSettings` | `ACTION_APP_NOTIFICATION_SETTINGS`. The plugin has no activity, so it can't show the runtime `POST_NOTIFICATIONS` prompt; the setup screen sends you to the switch instead. |
| `openAppInfo` | `ACTION_APPLICATION_DETAILS_SETTINGS` (where "Allow restricted settings" lives) |
| `requestBatteryExemption` | `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, falling back to the battery optimisation list |
| `openAutostart` | tries the OEM screens below, then App info |

**Details**
- `serviceEnabled` parses `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` for our component.
- **Autostart screens** (package / activity):
  - `com.miui.securitycenter` / `com.miui.permcenter.autostart.AutoStartManagementActivity`
  - `com.coloros.safecenter` / `…permission.startup.StartupAppListActivity`
  - `com.coloros.safecenter` / `…startupapp.StartupAppListActivity`
  - `com.oplus.safecenter` / `…permission.startup.StartupAppListActivity`
  - `com.oppo.safe` / `…permission.startup.StartupAppListActivity`
  - `com.vivo.permissionmanager` / `…activity.BgStartUpManagerActivity`
  - `com.iqoo.secure` / `…ui.phoneoptimize.AddWhiteListActivity`
  - `com.huawei.systemmanager` / `…startupmgr.ui.StartupNormalAppListActivity`
  - `com.letv.android.letvsafe` / `…AutobootManageActivity`
  - `com.asus.mobilemanager` / `…powersaver.PowerSaverSettings`

### 3.6 Android resources

**`AndroidManifest.xml`**
- Add `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and `POST_NOTIFICATIONS`.
- v0.2.0: these live in the `reelbot_native` plugin's manifest (IMPLEMENTATION §0.1), with the label written as "Reel Bot".
- Add the service:

```xml
<service android:name=".ReelCounterService" android:exported="false"
    android:label="@string/app_name"
    android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
  <intent-filter><action android:name="android.accessibilityservice.AccessibilityService"/></intent-filter>
  <meta-data android:name="android.accessibilityservice" android:resource="@xml/reel_counter_service"/>
</service>
```

**`res/xml/reel_counter_service.xml`**
- `accessibilityEventTypes="typeWindowStateChanged|typeWindowContentChanged|typeViewScrolled"`
- `accessibilityFlags="flagReportViewIds|flagIncludeNotImportantViews"`
- `canRetrieveWindowContent="true"`
- `notificationTimeout="100"`
- **No `packageNames` filter.** The service must notice when you leave Instagram/YouTube, and Phase 3 reads the system share sheet.

**`res/values/strings.xml`**
- v0.2.0: the strings are `reelbot_service_summary` / `reelbot_service_description` in the plugin, so they can't clash with the app's.
- A summary and description that say it reads the Reels/Shorts screens to count them, keeps everything on the phone, and never taps, types or scrolls (until you turn on auto-Save in Phase 3).

**`app/build.gradle.kts`**: `testImplementation("junit:junit:4.13.2")`.

---

## 4. Flutter side (Phase 2)

### 4.1 `lib/native/counter_bridge.dart`

A thin wrapper over the `reelbot/counter` channel.

**Typed results**
- `DayCount {date, app, reels, ms, unknown}`
- `SeenItem {app, fp, firstSeen, dwellMs, author, caption}`
- `CounterStatus {serviceEnabled, serviceRunning, batteryExempt, notificationsAllowed, sdkInt, manufacturer, capture}`
- `PendingItem {id, url, app, author, caption, onScreenText, createdAt, status}` (Phase 1)

**Helpers**
- `today()`: sums today's rows per app.
- `history(days: 14)`: groups rows by date.

### 4.2 `lib/ui/today_screen.dart`
- **Setup card** if `!serviceEnabled`; it opens the setup screen.
- **Detection warning** if today's `unknown ≥ 5` and `≥ 30%` of the total: "Counting may be broken after an Instagram/YouTube update", with a button to the debug screen.
- **Big number:** reels + shorts today. Under it, minutes on the Reels/Shorts screen, and per-app chips (Instagram n · YouTube n).
- **History:** the last 14 days, each with a simple bar.
- **Refresh:** every 3 s while visible, and on app resume.
- A debug button opens the debug screen.

### 4.3 `lib/ui/setup_screen.dart`
A checklist that re-checks `status` on resume:
1. *(Android 13+)* **Allow restricted settings.** Button: `openAppInfo`. Text: "⋮ → Allow restricted settings".
2. **Turn on Reel Bot in Accessibility.** Button: `openAccessibilitySettings`.
3. *(Android 13+)* **Allow notifications** (for the unknown alert and digest).
4. **Battery: unrestricted.** Button: `requestBatteryExemption`.
5. *(Xiaomi, Redmi, Poco, Oppo, Realme, OnePlus, Vivo, iQOO, Huawei, Honor)* **Allow Autostart.** Button: `openAutostart`.

### 4.4 `lib/ui/debug_screen.dart`
- Today's unknown count per app.
- **"What the counter sees now"** (`debug_state["now"]`).
- **Switch: Capture screen structure** (`setCapture`). With it on, open a reel and come back; `tree_instagram` / `tree_youtube` show the real view ids, with a **Copy** button. Use this to write (§3.0) and later fix the id lists in `DetectionRules.kt`.
- Today's seen items: time, app, author, caption and dwell seconds.

---

## 5. Tests

The full catalogue, with IDs, levels, fixture rules and commands, is [TESTS.md](TESTS.md). Each section above names the endpoints it implements; [ENDPOINTS.md](ENDPOINTS.md) lists the tests for each endpoint.

Before every commit that changes code: `flutter analyze`, `flutter test`, `./gradlew :app:testDebugUnitTest`. Before every release: also `flutter build apk --release` and the live and manual checks in TESTS.md §6–7.

---

## 6. Phase 3: bubble + optional auto-Save

| File | Behaviour |
|---|---|
| `OverlayBubble.kt` | A `TYPE_ACCESSIBILITY_OVERLAY` bubble you can drag, shown while `tracker.active`. Tapping it expands to **[Today: N]** and **[Save]**. |
| Bubble **Save** (default) | Insert a `pending_items` row (author, caption, on-screen text, no URL) and show "Now tap Share → Reel Bot". The share receiver attaches the URL to this row (§2.2). |
| `SaveAutomator.kt` | **Off by default** (setting "Auto-Save (experimental)"). Steps below. Each step has a 1.5 s timeout; on a miss, press Back, keep the row, and show "Tap Share → Reel Bot to attach the link". |

`SaveAutomator.kt` steps:
1. Insert a `pending_items` row (author, caption, on-screen text, no URL).
2. Click the reel's **Share** button, found by the rules.
3. Instagram only: click **Share to…** / **More**, which opens the system share sheet.
4. In the system share sheet (`com.android.intentresolver`), click the **Reel Bot** node. If it isn't visible, scroll once and retry.

Log each attempt's result in `debug_state`; the debug screen shows the success rate. **If it stays below 90% on your phones, delete `SaveAutomator.kt`.**

**Never** automate anything else: no scrolling, likes, follows or opening profiles.

**v0.3.0 as built:**
- Step 3 runs for both apps: if "Reel Bot" isn't in the sheet, it presses "Share to…" / "More" once (YouTube's own sheet can need it too), then scrolls once.
- The share button is found by guessed ids (`clips_share_button`, `direct_share_button`, `row_feed_button_share` / `reel_dyn_share`, `share_button`, `reel_share_button`), then by its "Share" / "Send" description. Replace the ids from a capture, as for §3.2.
- The system share sheet (`com.android.intentresolver`, `com.google.android.intentresolver`, `android`) is on the tracker's ignored list, so opening it doesn't end the session.
- The switch is in Settings (`setAutoSave`); attempts are counted in `debug_state` (`autosave_tries`, `autosave_ok`, `autosave_last`).

## 6b. v0.5.0: providers, chat, privacy, look

- **Keys:** several Gemini keys (one per line in secure storage). The runner starts each reel on the next key (`gemini_turn`); a 429 or bad key moves that reel to the following key. OpenAI and Claude keys make notes from 6 frames when no Gemini key can; Groq is chat only.
- **Tokens:** first Gemini attempt sends `thinkingLevel: minimal`, `mediaResolution: LOW` and video at 0.5 fps; a 400 retries without them. Shorter prompt, 1–2 sentence summary.
- **Chat** (`ui/chat_screen.dart`) replaces *Ask your library*: any provider with a key, all notes in the system prompt, last 10 turns.
- **Privacy:** watched reels are counted by fingerprint only (§3.3). Feedback is the only thing sent on purpose, as a GitHub issue the user submits.
- **Look:** `ui/theme.dart` (v0.6.0: the purple→pink→orange→yellow Reels gradient on black/white surfaces; Reel Bot keeps its own play mark, never Instagram's logo), first-run `ui/intro_screen.dart` (spinning gradient ring, three pages, *Slide to unlock* that bursts the gradient across the screen), library cards with the short summary.
- **Home (v0.6.0):** tabs are Ask (chat, with a provider + model picker), Today, Library.
- **Seen / archive (v0.6.0):** `reel_brain.db` version 2 adds `seenAt` and `archived`. Opening a note marks it seen; unseen notes show a gradient dot. On each library load, seen notes saved more than 3 days ago move to the Archive (searchable, restorable, still used by chat and export). Unseen notes never auto-archive.
- **Notifications (v0.6.0):** after a background run that finished notes, "Note ready: <title>" (`notifyNotes`). The 9 pm digest on an empty day nudges instead of showing zeros.
- **v0.9.1:** the cascade no longer pauses all of Instagram on a login wall. `StepResult.Limited` (HTTP 429) still pauses 30 min; `LoginWall` (login redirect, `require_login`) only skips that step, so the embed player and the other steps still run. If every step walls and nothing is found, the reel is retried after 10 min, up to 3 runs, then the runner makes do with what it has.
- **v0.9.0:** the bubble, its Save and the experimental auto-Save are removed (`OverlayBubble.kt`, `SaveAutomator.kt`, `addBubbleSave`, `ShareUrls.shouldAttach`, `setAutoSave`). Saving is only Share → Reel Bot (links, posts, photos); the counter is read-only again. Phase 3 (§6) is withdrawn. Library and Archive gain multi-select: long-press a note, tap others, then Mark read, Archive / Restore or Delete (with Undo).
- **v0.8.2:** fixes tabs drawing over each other: `FadingTabs` keeps each tab's fade outside its `TickerMode` (v0.8.1 put it inside, so a hidden tab's fade-out froze half-way). Fewer controls: the theme toggle lives only in Settings; Settings opens from Ask; Set up counting and Counter debug moved into Settings; library cards lost their delete and fallback icons (delete is a swipe or on the note), the swipe hint is gone, and empty filter chips are hidden. Repo renamed to `nevil-sanish/reel-brain`.
- **v0.8.1 (layout):** tabs are **Ask** (today strip, chat with the ask bar at the bottom, saved chats in `reel_brain.db` v3 `chats`, history sheet, model picker), **Insights** (`ui/insights_screen.dart`: Week/Month, minutes per day, reels by hour from `seen_items.first_seen` via the new `hourly` channel method, weekday averages) and **Library** (All / Reels / Shorts / Posts / Photos filters; cards show title and summary only). Notes show the summary first and *Show full analysis* expands points, tags, source and fallback details. Palette is greens only (`Brand.forest … lime`), light by default, dark via the sun/moon button or Settings (saved as the `dark` flag). Pages open with a fade-and-swell "liquid" transition; tabs cross-fade.
- **v0.8.0 (photos and posts):** the share receiver also takes `image/*`: the picture is copied into `files/photos/<time>.jpg` (≤ 1280 px JPEG), queued as `photo:<path>` with app `photo`, analysed as an image and shown on its note. Instagram parsers now fill `IgMedia.images` (every still of a photo post or carousel, carousel videos left out); a post with no video sends up to 10 of them in one request and makes a full note instead of a caption + thumbnail one.
- **v0.7.0 (liquid glass):** `ui/liquid.dart`: `LiquidBackground` (four slowly drifting radial-gradient blobs in the brand colours, one `CustomPaint`), `Glass` (backdrop blur 24, tint, hairline edge, top highlight), `LiquidScaffold` (pushed screens draw their own background; the home draws one behind all tabs), `GlassTabBar` (floating frosted pill, gradient on the selected tab). Theme: glass-tinted cards, search bars, chips and inputs; stadium buttons; floating snackbars; Cupertino page transitions; heavier, tighter titles. Chat opens on a large glass ask bar mid-screen with the title and suggestions; sending glides the bar to the bottom and the conversation takes over.
- **v0.6.2:** Instagram embed-player step (ENDPOINTS IG-EMBED-PLAYER) to stop "text only" notes; Instagram text-only notes are re-queued once on update, and any note without video has *Try again with the video* (re-queues its `pending_items` row and removes the note). Cards swipe left to delete (with Undo) and right to archive / restore, and have a delete button. Cards show when the note was saved ("3h ago"); the note shows the full date and time.
- **v0.6.1:** notes are shorter (prompt asks for a one-sentence summary, up to 3 points and 3 tags; the note screen shows only those, the fallback reason is a tooltip). Haptics via Flutter's `HapticFeedback` (Android touch feedback, no permission): tab switch, send / answer, model pick, card open, archive, delete, intro Next, slide-to-unlock ticks and the unlock thud.
- **Models (v0.6.0, token cost first):** Gemini Flash-Lite then 3.6 Flash; OpenAI `gpt-6-luna`; Claude `claude-haiku-5-5`, thinking off, low effort; Groq `openai/gpt-oss-20b`.

## 7. Phase 4: daily digest

`DigestWorker.kt` (Kotlin `WorkManager`, periodic, aimed at about 21:30). If the app's `last_opened` is before today, post one notification: "N reels · M min · K saved: titles…". Titles come from items already analysed in the background (status `done` / `caption+thumbnail` / `text-only`); if none are analysed yet, show "N reels · M min · K saved" without titles. Tapping it opens the app.

**v0.4.0 as built:**
- `DigestWorker` runs **hourly** (unique periodic work `reelbot_digest`, scheduled when the plugin attaches) and posts only after 21:00, once a day (`digest_posted` pref), and only if `last_opened` isn't today. A single 24 h job drifts away from 21:30.
- `last_opened` is written by `markOpened`, which Flutter calls on start and on every resume.
- Titles come from a new `pending_items.title` column (`counter.db` version 3), filled by `setPendingStatus`, because Kotlin never opens Dart's `reel_brain.db`. "K saved" counts `pending_items` rows created since local midnight.

## 8. Before sharing with friends: `docs/INSTALL.md`

One page, one screenshot per step:
1. Download the APK from GitHub Releases.
2. If Play Protect blocks it: pause Play Protect while installing (or `adb install`).
3. *(Android 13+)* App info → ⋮ → Allow restricted settings.
4. Accessibility → Reel Bot → On.
5. Notifications, battery unrestricted, Autostart (Xiaomi/Realme/Oppo/Vivo).
6. Get a free Gemini key at aistudio.google.com and paste it in Settings.
7. Test: share one reel to Reel Bot and check it appears in the Library.
