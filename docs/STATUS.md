# Reel Bot: project status

Written 2026-11-06; current as of **v0.9.4**, plus unreleased work on `main` after it (§2.1). This page says what has been built, how it was checked, and what work is left, in detail. The other docs go deeper: [PLAN.md](PLAN.md) for intent, [IMPLEMENTATION.md](IMPLEMENTATION.md) file by file (with a per-version log), [ENDPOINTS.md](ENDPOINTS.md) for every network call, and [TESTS.md](TESTS.md) for every test ID.

- [1. Where things stand](#1-where-things-stand)
- [2. What has been done](#2-what-has-been-done)
- [3. How it was checked](#3-how-it-was-checked)
- [4. Work still to do](#4-work-still-to-do)
- [5. Known limitations and risks](#5-known-limitations-and-risks)
- [6. How to continue](#6-how-to-continue)

---

## 1. Where things stand

| | |
|---|---|
| **Latest release** | [v0.9.4](https://github.com/nevil-sanish/reel-brain/releases/tag/v0.9.4): a signed APK for Android 10+, marked pre-release |
| **Releases so far** | 18 (v0.1.0 to v0.9.4), each with an APK and `SHA256SUMS` |
| **Repository** | `nevil-sanish/reel-brain` (renamed from `reel-notes-bot`; the old links redirect) |
| **Code** | Flutter app ~4,200 lines in `mobile/lib`; Kotlin plugin ~1,600 lines in 11 files |
| **Automated tests** | 34 Dart and 59 Kotlin, all passing; `flutter analyze` clean |
| **Seen on a real phone** | Yes, from the user's screenshots on 2026-11-06: the counter counted 41 reels and shorts in a day, an Instagram reel became a full note from its video, and the Ask, Insights and Library tabs render. Since then, checked over ADB on a Nothing A059 (Android 16, 90 Hz): the first Instagram run (item 2), scrolling (item 11), the setup checklist (item 4) and surviving a kill (item 5). It found and fixed three bugs (§2.1 *Unreleased*). |

**Product in one line.** You share Instagram Reels, Instagram posts, YouTube Shorts or photos to Reel Bot. It turns each into a short AI note using your own key, lets you chat with all your notes, and (optionally) counts how many reels and shorts you watch. Everything stays on the phone.

---

## 2. What has been done

### 2.1 By release

| Version | What it added |
|---|---|
| **v0.1.0** | Phase 1. A transparent share receiver: share → "Saved ✓" and you stay where you were. A queue in `counter.db`. The Instagram logged-out cascade. YouTube links sent straight to Gemini. Background analysis every 15 min. The Library, search, *Ask your library*, and Export/Import. The signing key is created outside the repo. |
| **v0.1.1** | The Library shows *why* an item is waiting (the Gemini HTTP status, no network, an Instagram pause, a held lock). Unexpected errors now mark the item failed instead of leaving it stuck. |
| **v0.2.0** | Phase 2, the counter. An Accessibility service, fingerprinting, the tracker (1.5 s dwell, per-day dedupe, screen time), the counter tables, the Today screen, the setup checklist, a debug screen with screen capture, and an alert when reels can't be read. |
| **v0.3.0** | Phase 3: a floating bubble with Today and Save, plus an experimental auto-Save. *(Removed in v0.9.0.)* |
| **v0.4.0** | Phase 4: the evening digest (an hourly worker that posts after 21:00 on days the app wasn't opened). Note titles are passed from Dart to Kotlin. |
| **v0.5.0** | Chat with any provider. Several Gemini keys used in turn. OpenAI and Claude as fallbacks (from video frames). Fewer video tokens (minimal thinking, low media resolution, 0.5 fps). YouTube sent as a `watch?v=` URL. Instagram reads the rendered reel page. Watched reels stored as fingerprints only. Feedback through a GitHub issue. A new theme and intro. |
| **v0.6.0** | Chat became the home tab, with a provider and model picker. Cheaper models first. Chat sends only the notes that match. The Reels-gradient theme and a slide-to-unlock intro. A seen/unseen dot and a 3-day archive. A "Note ready" notification and a 9 pm nudge. |
| **v0.6.1** | Shorter notes. Haptic feedback across the app. |
| **v0.6.2** | Instagram **embed-player** step (cascade step 2). Instagram notes made from text only were retried once. A *Try again* button. Swipe to delete or archive. Saved times on notes. |
| **v0.7.0** | The liquid-glass look: a drifting background, frosted surfaces, a floating tab bar. The chat starts from a big ask bar. |
| **v0.8.0** | Shared **photos and screenshots** are analysed. Instagram **photo posts and carousels** send every image (up to 10). |
| **v0.8.1** | A green theme (light by default, dark toggle). Liquid page and tab transitions. Saved chats with a history sheet. A full **Insights** tab. Library filters. A compact note with a full-analysis toggle. |
| **v0.8.2** | **Fix:** the tabs drew on top of each other (with a regression test). Fewer buttons. The README explains the workflow. The repo was renamed. |
| **v0.9.0** | The bubble, Save and auto-Save were **removed** at the user's request; saving is Share → Reel Bot only. **Multi-select** in the Library and Archive (mark read, archive or restore, delete with Undo). |
| **v0.9.1** | **Fix:** a login page no longer pauses all Instagram fetching for 30 min. It skips that one step; only HTTP 429 pauses; a reel where every step was walled is retried after 10 min, up to 3 times. |
| **v0.9.2** | **Richer notes**: overview bullets in simple words that cover every important point, plus the full detail behind a toggle (summary, every key point, mentions, tags) and **Re-analyse**. Chat uses full notes, archive included. **Readable Insights** (labelled bars, time-of-day blocks, average per active day). A new **Ask home** (greeting, today strip, *Recently saved*, suggestions built from your tags). |
| **v0.9.3** | Search covers the overview and mentions. Settings → Notes → *Re-analyse old notes* brings pre-v0.9.2 notes to the new format. Photo files from deleted notes are cleaned up on start. *When you watch* is ranked by minutes watched. |
| **v0.9.4** | Export and Import include **saved chats**. **Several photos** can be shared at once (one note each). An **update banner** when GitHub has a newer APK. [INSTALL.md](INSTALL.md) for friends; PLAN.md matches the product. |
| *Unreleased* | **Time from Usage access:** Insights and the Ask home show time in Instagram and YouTube from Android's usage data; reel counting through Accessibility is optional. Setup becomes *Set up Insights*, and **both parts are optional**: with neither on, the home strip hides and Insights says how to turn them on. **App icon:** the brand mark (green gradient, white play glyph) as an adaptive icon with a themed-icon layer, replacing Flutter's default. **Fixes found on the phone:** the setup checklist said Accessibility was off when it was on (now read from `AccessibilityManager`); a private post's login wall was shown as "Instagram is limiting requests"; the background job closed the open app's notes database when it finished (sqflite shares one connection per path), so every screen failed until restart; found on the phone. The winning Instagram step and each Gemini attempt are logged (`ReelBot`). Settings → Appearance → **Reduce effects** (a still background, no blur). Channel and background-task integration tests (Robolectric on the Kotlin side) and the Instagram login-wall fixture. |

### 2.2 Features as they work today

#### Saving (share in)
- **Accepted:**
  - Instagram links (`/reel/`, `/reels/`, `/p/`, `/tv/`), with tracking parameters stripped;
  - YouTube Shorts (`/shorts/` and `youtu.be`);
  - images (`image/*`) shared from any app, one or several at once (one note per image).
- **Photos** are decoded, shrunk to at most 1280 px, saved as JPEG in `files/photos/`, and queued as `photo:<path>`.
- **No overlay:** there's no floating button over other apps; the only way to save is the system share sheet.
- **Files:** `ShareReceiverActivity.kt`, `ShareUrls.kt`, `CounterDb.addShared` and `addPhoto`.

#### Analysis (the queue runner)
- **Runs:** in the background every 15 min with network (`workmanager`), and whenever the app opens or resumes. A lock row stops two runs at once.
- **YouTube:** the link is sent to Gemini as `fileData` with a `watch?v=` URL. If Gemini refuses, the note is made from YouTube oEmbed's title and thumbnail.
- **Instagram reel:** a cascade of 7 steps, each 5 s apart, that stops at the first video:
  1. embed HTML;
  2. embed player (a WebView presses play and catches the video);
  3. post page JSON;
  4. logged-out GraphQL;
  5. web GraphQL;
  6. oEmbed (metadata only);
  7. Apify, if a token was added.

  The video is downloaded (≤ 100 MB), sent inline (≤ 20 MB) or through the Gemini Files API, then deleted. Failure handling:
  - a login page skips that step;
  - an HTTP 429 pauses Instagram for 30 min;
  - a reel where every step is walled is retried after 10 min, up to 3 times;
  - a private or deleted post is not retried for 1 h.
- **Instagram post or carousel:** every still image (videos are skipped), up to 10, sent in one request.
- **Photo:** the JPEG is sent as one image.
- **Fallbacks:** the caption and thumbnail, then the text only. The note says which, and offers *Try again*.

**Providers.**
- **Gemini:** keys taken in turn, one reel per key. A 429 or a rejected key moves that reel to the next key. Models: `gemini-3.5-flash-lite`, then `gemini-3.6-flash`.
- **OpenAI** (`gpt-6-luna`) and **Claude** (`claude-haiku-5-5`, thinking off, low effort): used when no Gemini key can take the reel. They get 6 frames (no audio) or the images.
- **Groq** (`openai/gpt-oss-20b`): chat only.

**Note format** (v0.9.2):
- title;
- **overview**: 3–6 short bullets;
- summary: 2–4 sentences;
- **keyPoints**: up to 12;
- **mentions**: tools, people, links;
- tags: 3–5.

**Token savers:** cheapest models first; on Gemini, minimal thinking, low media resolution and 0.5 fps on the first try, retrying without them if a model rejects them; videos are never downloaded for YouTube.

**Files:** `pipeline/runner.dart`, `gemini.dart`, `providers.dart`, `apify.dart`, `background.dart`; Kotlin `InstagramFetcher.kt`, `IgCascade.kt`, `IgParse.kt`.

#### Storage (all on the phone)
- **`counter.db`** (Kotlin, version 4):
  - `pending_items`: the queue, its statuses and note titles;
  - `seen_items`: fingerprint, time and dwell only, with no content since v0.5.0;
  - `screen_time`, `unknown_items`, `debug_state`.
- **`reel_brain.db`** (Dart, version 4):
  - `reels`: notes, with seen/archived, overview and mentions;
  - `chats`: saved conversations;
  - `meta`: the lock.
- **Encrypted secure storage:** API keys, the Gemini rotation turn, and flags (dark mode, reduce effects, intro seen, one-time migrations).
- **Export:** `Downloads/ReelBot/library.json` (notes and saved chats) plus one Markdown file per note. Import merges notes by URL and chats by first question and time.

#### App (three tabs)
- **Ask:**
  - a greeting and today's counts (reels, shorts, minutes);
  - a *Recently saved* row and suggestions built from your top tags;
  - the ask bar at the bottom, with a provider and model chip;
  - chats saved automatically, a history sheet (reopen, swipe to delete) and *New chat*.
- **Insights:**
  - Week or Month view;
  - a hero card (total, time watched, average per active day, today);
  - reels per day with labelled bars;
  - Night, Morning, Afternoon and Evening blocks with the peak hour;
  - a weekday chart once 7 active days exist;
  - today's split between apps.
- **Library:**
  - search, and filters (All, Reels, Shorts, Posts, Photos) that hide empty categories;
  - cards showing the title and two overview bullets, with an unseen dot;
  - swipe left to delete (Undo), right to archive;
  - long-press multi-select (mark read, archive or restore, delete);
  - an Archive screen with the same tools. Seen notes archive themselves after 3 days.
- **Note:**
  - for photos, the image;
  - the title, then the overview bullets;
  - *Show full analysis*: detail, numbered points, mentions, tags, source, *Re-analyse* or *Try again*;
  - copy link, archive, delete.
- **Settings:**
  - a privacy card;
  - AI keys: several Gemini keys, plus OpenAI, Claude, Groq and Apify;
  - Appearance (dark mode, reduce effects);
  - Insights (Set up Insights, Counter debug);
  - Backup (Export, Import);
  - Feedback;
  - the version number.
- **Look and feel:**
  - green theme, white by default, dark mode saved;
  - a drifting liquid background and frosted cards;
  - a floating glass tab bar;
  - liquid page transitions and cross-fading tabs;
  - haptics on key actions;
  - a first-run intro with *Slide to unlock*.

#### Time in the apps (Usage access)
- **Source:** `UsageStatsManager.queryEvents` for Instagram and YouTube; an app counts as in front while any of its screens is resumed, until the last one pauses or the screen goes off (`AppUsage.kt`).
- **Checked on the phone, 2026-11-06:** recomputed from `dumpsys usagestats` for the last 24 h, Instagram 33.7 min and YouTube 12.8 min, and the app's logic now gives the same. The first version ended a session whenever Instagram opened an overlay (comments, browser, modal) and showed ~20% too little.
- **Shown:** Ask home (Instagram and YouTube time today), Insights (time per day, time-of-day blocks, weekday, apps today). It's time in the whole app, not only Reels or Shorts.
- **Setup:** Settings → Set up Insights → *Allow usage access*. No Accessibility needed.

#### Counting (optional, Accessibility)
- **Reading the screen:** reads Instagram Reels and YouTube Shorts screens with `DetectionRules`, from starting-point view ids plus a fallback that reads text in the bottom half of the screen.
- **Fingerprint:** a SHA-1 of app, author, the first 40 caption characters, audio and title, with a like-count bucket for reels without a caption.
- **Tracker:** a reel counts after 1.5 s on screen; one entry per day; a 5 s gap ends the session; screen time is flushed every 30 s; a 1 s tick keeps time while a video plays with no events.
- **Unknown alert:** if 5 or more reels in a day (and at least 30% of them) can't be read, one notification is posted that day.
- **Read-only:** it never taps or scrolls.
- **Files:** `ReelCounterService.kt`, `DetectionRules.kt`, `ReelTracker.kt`, `CounterDb.kt`.

#### Notifications
- **"Note ready" / "N notes ready":** after a background run finishes notes.
- **Evening digest:** after 21:00 on days the app wasn't opened. It says "N reels · M min · K saved: titles", or a short nudge on an empty day.

#### Privacy
- **What leaves the phone:**
  - reels you share, to the AI provider you chose, with your key;
  - logged-out Instagram page requests for reels you shared;
  - feedback, as a GitHub issue you review before posting;
  - nothing from Usage access: app times stay on the phone;
  - one request a day to GitHub's releases list, for the update banner (no token, nothing about you).
- **What never does:** no analytics, no tracking, no server. Watched reels are counted by hash, never recorded. Turning debug capture off deletes what it recorded.

### 2.3 Documentation done
- **[README](../README.md):** the user workflow and the technical workflow (components, stores, jobs, how each item type is analysed, counting, chat, every outside service and what is sent to it).
- **PLAN, IMPLEMENTATION, ENDPOINTS, TESTS, RELEASES:** kept in step, with a change-log row per version.

---

## 3. How it was checked

| Check | Result |
|---|---|
| `flutter analyze` | clean (v0.9.4 and the unreleased work after it) |
| Dart tests (`mobile/test`, 34) | passing. They cover the background task body, the channel mapping (pending items, Instagram results and errors), Reduce effects, the runner (YouTube, Instagram video, inline vs Files API, caption fallback, 429 handling, key rotation, the OpenAI frames fallback, photos, carousels, retry, Apify), export/import (with chats), the update check, the archive, saved chats, search over overview and mentions, the Insights helpers, the intro unlock with its haptic, tab fading, the multi-select card, and saved-time labels |
| Kotlin tests (`:reelbot_native:testDebugUnitTest`, 59) | passing. They cover the plugin through a real `MethodChannel` (Robolectric), share-URL parsing, the Instagram parsers (synthetic fixtures, login wall included), the cascade rules (throttle, pauses, login walls, single-flight), fingerprints, the tracker, detection rules, the unknown alert and the digest rules |
| Release builds | every APK built with `flutter build apk --release`, checked with `apksigner` (signer `CN=Reel Bot, O=nevil-sanish`), and published with a SHA-256 |
| On a phone | only what the user's screenshots show (§1). No live checks (`T-LIVE-*`) or manual checks (`T-MAN-*`) have been run |

---

## 4. Work still to do

In priority order. Each item says what, why, and what "done" looks like.

### P0: verify on a real phone (nothing below is known to work until this is done)

1. **Phase 1 exit test (T-MAN-02, T-BG-02).**
   - **Test:** share 10 Instagram reels and 10 Shorts with the app closed, and wait 30 min.
   - **Why:** the background job only runs on a device, and Android's Doze and OEM battery savers can delay it.
   - **Done when:** all 20 have notes, and the "Note ready" notification appears.
2. **Instagram success rate (T-LIVE-01…10).**
   - **Test:** for a fixed set of public reels, a carousel, a photo post and a private post, record which cascade step won.
   - **Why:** the parsers were built from documented shapes and tested on **synthetic** fixtures. Instagram changes its pages often, and the embed-player step (v0.6.2) has never been tested against Instagram.
   - **Done when:** at least 80% of public reels get the **video** without Apify (the PLAN's exit bar), and a real captured response is saved beside each synthetic fixture.
   - **First run, 2026-11-06 (Nothing A059, Android 16):** 6 shared (4 reels, 1 post, 1 more waiting). All 5 analysed came from the video or images, none needed Apify: 4 by the embed player (step 2), 1 by logged-out GraphQL (step 4). The sixth was a **private account's post** (a 39-character code): every step hit the login wall, so it waits 10 min and retries up to 3 times, as designed. The library wrongly called that "Instagram is limiting requests"; fixed to say Instagram wants a login. Promising, but too few to call: repeat with 20+ public reels shared a minute apart. The winning step is now logged: `adb logcat -s ReelBot`.
3. **Counter accuracy (T-MAN-03).**
   - **Test:** watch 20 reels and 20 Shorts with swipe-backs, half-swipes, a refresh, rewatches and reels without captions.
   - **Why:** the view ids are the docs' starting guesses. Counting worked on the user's phone, but its accuracy hasn't been measured.
   - **Done when:** the count is within ±1. If it's off, capture `tree_instagram` / `tree_youtube` from Settings → Counter debug, fix `DetectionRules.kt`, and add the captures as **T-RULE-06** fixtures.
4. **Setup checklist on several brands (T-MAN-04, T-CH-04).**
   - **Test:** every button on a stock Android phone and on a Xiaomi or Realme, on Android 13+ (restricted settings).
   - **Done when:** each button opens the right system screen.
   - **Nothing A059, Android 16 (2026-11-06):** the checklist said Accessibility was off while it was on and bound, because the raw `ENABLED_ACCESSIBILITY_SERVICES` read didn't match; fixed by asking `AccessibilityManager`. After the fix every row shows done, and all five intents behind the buttons resolve to the right Settings screen. Still to do: a Xiaomi or Realme (Autostart).
5. **Survives reboot and kill (T-MAN-05).**
   - **Done when:** counting and background analysis resume after a reboot and after the app is swiped away.
   - **Kill, 2026-11-06:** after the process was killed (`am crash`), Android restarted it within 8 s with the counter service bound and both jobs (analyse, digest) still scheduled. `am kill` doesn't kill it at all while the Accessibility service is bound. A **force stop** (App info → Force stop) removes the jobs until the app is opened again; that is Android's rule. Still to do: a reboot.
6. **Unknown alert fires (T-MAN-06).**
   - **Test:** rename one detection id on purpose and watch reels.
   - **Done when:** one alert appears that day.
7. **Digest (T-MAN-07).**
   - **Test:** after 21:00, let the hourly job run (or wait for its window and then run `adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler app.reelbrain <id>`; WorkManager delays a forced run that comes before the period is up, and the ids need the `-n` namespace).
   - **Done when:** the notification shows titles, or counts only, or the nudge, as expected.
8. **Fresh install (T-MAN-01).**
   - **Test:** install the release APK on Android 13+ and note any Play Protect prompt.
9. **Other providers live.**
   - **Test:** make one note each with an OpenAI key and a Claude key, and send one chat message each through Groq, OpenAI and Claude.
   - **Why:** their request shapes come from the providers' docs, but no real key has been used.
   - **Done when:** each returns a valid note or answer.
10. **Gemini token savers live.**
    - **Test:** check that `videoMetadata.fps` and `mediaResolution` are accepted by `generateContent` (the docs only show them on the newer Interactions API).
    - **Why:** if they're rejected, every reel costs an extra request, because the retry without them still works.
    - **Done when:** a log or debug check shows the first attempt succeeding.
    - **Logging added:** each Gemini call now logs `ReelBot gemini <model> ok, token savers on|off` or the rejection; read it with `adb logcat | grep ReelBot` while a reel is analysed.
11. **Performance.**
    - **Test:** scroll each tab on a mid-range or older phone.
    - **Why:** the background blur (`BackdropFilter`) and the animated background can stutter on weak GPUs.
    - **Done when:** smooth, or a "reduce effects" switch is added.
    - **Switch added** after v0.9.4 (Settings → Appearance → *Reduce effects*, T-UI-07).
    - **Measured on the Nothing A059 (mid-range, 90 Hz), 2026-11-06,** from SurfaceFlinger frame times while swiping the Library 12 times: effects on, 0% and 1.6% of frames late (the very first scroll after a fresh install was 17.7%, while shaders compile); Reduce effects on, 0% and 0.8%. Smooth either way on this phone. Found: with effects on the background redraws at ~90 fps even when idle, which costs battery; worth pausing it when nothing moves. Still to try: an older or low-end phone.

### P1: product gaps (small, well understood)

12. ✅ **Done in v0.9.3.** **Search doesn't look at the new fields.** `LibraryDb.reels(query:)` searches the title, summary, key points, tags, author and caption, but not `overview` or `mentions` (added in v0.9.2). Add both columns to the `LIKE` expression, plus a test.
13. ✅ **Done in v0.9.3** (Settings → Notes → *Re-analyse old notes*, with a token warning). **Re-analyse all old notes at once.** Notes made before v0.9.2 have no overview or mentions; for now each has to be re-analysed by hand. Add Settings → *Re-analyse all notes*: for each note with an empty overview that still has a queue row, re-queue it and drop the note, like `AppServices.retry`. Warn that it costs tokens. Waiting on the user's decision.
14. ✅ **Done in v0.9.3** (orphan photos are deleted on each start, so Undo still works until then). **Photo files left behind on delete.** Deleting a photo note doesn't delete its `files/photos/*.jpg`, because Undo needs it. Delete the file once the Undo snackbar has closed, or sweep orphan files on start.
15. ✅ **Done in v0.9.3** (the blocks and peak hour are ranked by minutes watched; counts are used until any time is recorded). **"When you watch" uses counts, not minutes.** The `hourly` query already returns `ms` per hour. Show minutes next to the count, or let the user choose.
16. **Watch time looks low.** *Mostly answered after v0.9.4:* time now comes from Usage access (whole-app time), so the counter's Reels-only time is no longer the headline number. For example, 41 reels in 8 min. Screen time only counts while the Reels/Shorts screen is recognised, and a 5 s gap without events ends the session. Check this against a stopwatch during the T-MAN-03 test, and tune `maxGapMs` or the 1 s tick if it under-counts.
17. ✅ **Done in v0.9.4** (one note per image; decoding moved off the main thread). **Sharing several photos at once.** Only `ACTION_SEND` (one image) is handled. Add `ACTION_SEND_MULTIPLE` to queue each image, or one note for the set.
18. ✅ **Done in v0.9.4** (`library.json` version 2; version 1 files still import). **Export leaves out chats.** `library.json` has notes only. Add `chats` to the export and import.
19. ✅ **Done in v0.9.4** (reads `/releases?per_page=1`, because `/releases/latest` skips pre-releases; a *Download* banner on the home screen). **Update check (T-REL-01, GH-RELEASE-LATEST).** Planned, never built: a banner when GitHub has a newer release with an `.apk` asset, which stays silent on a 403.
20. ✅ **Written in v0.9.4**, text only: the screenshots still need a phone. **`docs/INSTALL.md`.** Planned in PLAN §6 before sharing with friends: one page with one screenshot per step (download, Play Protect, restricted settings, Accessibility, battery, Autostart, Gemini key).
21. ✅ **Done in v0.9.4.** **PLAN.md is behind.** It still describes Phase 3 (the bubble and auto-Save), which was removed in v0.9.0, and doesn't mention photos, posts, chat or Insights. Update it to match the product.

### P2: engineering debt

22. ✅ **Done after v0.9.4** (`CounterPluginTest.kt` on Robolectric drives the plugin through a real `MethodChannel`; the task body is `analyseAndNotify`, tested with fakes. Opening the real stores in a background engine is still T-BG-02, on a phone). **Integration tests for the channel and background job (T-CH-01, T-CH-02, T-BG-01).** The Dart–Kotlin channel and the `callbackDispatcher` are only exercised on a device. Add Robolectric tests for `CounterPlugin`, and a Dart test that runs the dispatcher with fakes.
23. ✅ **Done after v0.9.4** (synthetic: a collected login page and a `require_login` reply; the page decode moved to `IgParse.page`. Add a real capture at the first live check). **Instagram login-wall fixture (T-IG-F04).** A captured login-wall page, to check the v0.9.1 rule that it only skips its own step.
24. **Kotlin build warnings.** As of v0.9.4 the "migrate to Built-in Kotlin" warning names only `workmanager_android` (already the newest version), not our plugin; wait for an upstream release. Our plugin still puts `kotlin-gradle-plugin` on its buildscript classpath for the `kotlin { compilerOptions }` block; drop it once AGP's built-in Kotlin covers that.
25. **One commit that doesn't build on its own.** `37cd366` (v0.5.0 work) changed `KeyStore` before the settings screen caught up in the next commit. History was left as it is; just don't bisect into that commit.
26. **Chat retrieval is keyword overlap.** Fine for hundreds of notes. If libraries grow to thousands, or questions are phrased differently from the notes, add on-device embeddings, or ask the model to pick note IDs first.
27. **The service's DB writes run on the main thread.** `ReelCounterService` writes to `counter.db` from Accessibility callbacks. That's fine at this volume; move it to a single background executor if profiling shows jank.

### P3: later, only if people use it (PLAN §6)

28. Remote updates to the detection rules, so an Instagram layout change doesn't need a new APK.
29. A weekly digest, or an email digest.
30. Transcription on the phone, to cut tokens further.
31. A Play Store listing (needs a privacy policy, the Accessibility declaration and target-API upkeep).

---

## 5. Known limitations and risks

- **Instagram can change or block logged-out access at any time.** The app never logs in, and only fetches reels you share, about one request every 5 s. The likely failure is that steps stop working, which gives "caption + thumbnail" notes, or a short IP rate limit; it doesn't put an account at risk. Apify is the paid fallback.
- **No automation of other apps.** At the user's request, there's no overlay and no tapping of Instagram's Share button. The counter only reads the screen.
- **Background timing isn't guaranteed.** Android may delay the 15-min job (Doze, battery savers). Opening the app always runs the queue straight away.
- **Model ids date from 2026-11-06.** Providers rename and retire models. When one disappears, change the lists in `Gemini.models` and `ChatModel.models`.
- **Sideloaded app on Android 13+.** Accessibility is greyed out until App info → ⋮ → *Allow restricted settings*.
- **Notes cost more tokens since v0.9.2**, because of the fuller detail. They still use the cheapest model of each provider first.

---

## 6. How to continue

**Toolchain:** Flutter 3.47 (Dart 3.13), JDK 21 and Android SDK 36 under `~/development`. Put them on `PATH` first.

```bash
cd mobile && flutter analyze && flutter test
```

```bash
cd mobile/android && ./gradlew :reelbot_native:testDebugUnitTest
```

```bash
cd mobile && flutter build apk --release
```

**Releasing:**
- **Signing key:** `~/.reelbot/reel-bot-release.jks`, with its password in `~/.reelbot/key.properties`; `mobile/android/key.properties` links to it. Back it up: without it, updates can't install over existing installs.
- **Each release:**
  1. bump `version:` in `mobile/pubspec.yaml` and `AppServices.version`;
  2. add a row to RELEASES.md, and to TESTS.md if tests changed;
  3. commit and push;
  4. build, run `apksigner verify`, and publish with `gh release create vX.Y.Z --prerelease` with the APK and `SHA256SUMS`.

**Where to start:**
- **Correctness:** begin with **P0** (§4), especially items 1–3, because every other item assumes the fetch and counter work on a real phone.
- **Small fixes:** items 12–15 are done in v0.9.3 and 17–21 in v0.9.4. Item 16 needs the T-MAN-03 stopwatch test on a phone; INSTALL.md needs its screenshots. P2 items 22–23 and the item 11 switch are done (unreleased). What's left without a phone is conditional: 24 waits on an upstream release, 26–27 only if libraries grow or profiling shows jank. Everything else needs a phone.
