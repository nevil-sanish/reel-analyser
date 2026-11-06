# Reel Bot: feasibility review and plan

**Written:** 4 Nov 2026 · **Revised:** 5 Nov 2026 (Share → summary first; see §6) · 6 Nov 2026 (matches v0.9.4: no bubble or auto-Save; photos, posts, chat and Insights added)
**Read with:** [IMPLEMENTATION.md](IMPLEMENTATION.md) (file-by-file guide), [ENDPOINTS.md](ENDPOINTS.md) (every network call), [TESTS.md](TESTS.md) (test catalogue), [RESEARCH.md](RESEARCH.md) (open-source survey), [RELEASES.md](RELEASES.md) (commits and releases).

Confidence tags: **[Certain]** = hard evidence, **[Likely]** = strong inference, **[Guessing]** = filling gaps.

---

## 1. What we're building

An Android-only app that:

1. turns the Instagram reels and posts, YouTube Shorts and photos you share to it into AI notes (with **your own** key: Gemini first, OpenAI or Claude as fallbacks) and keeps them in a searchable library with an archive;
2. lets you **ask** questions across all your notes (Gemini, OpenAI, Claude or Groq), with saved chats;
3. counts how many Instagram Reels and YouTube Shorts you watch each day, and for how long, and shows it in **Insights**;
4. at the end of the day, if you didn't open the app, shows a short digest notification.

Saving is only ever Share → Reel Bot. There's no floating bubble and no automation of other apps (removed in v0.9.0 at the user's request).

## 2. Decisions taken

| # | Decision |
|---|---|
| 1 | **v1 is for your own phone only.** Friends get it only after `docs/INSTALL.md` exists (a one-page guide with screenshots, see §4.6). Never on the Play Store, so Play-only rules (such as the ban on Accessibility automation) don't apply. |
| 2 | **Flutter for the UI, Kotlin for everything that runs in the background.** Flutter is kept only because about 80% of an older Flutter app already exists in git history (commit `5f0c001`, folder `mobile/`). The hard parts are all Kotlin: the share receiver, the Accessibility service, counting and the digest worker. |
| 3 | **Fully local.** All data stays on the phone, and every key is the user's own (Gemini; Apify is optional). There is no server, sign-in, credits or billing. |
| 4 | **Analysis runs in the background.** A Save only queues an item. A background job (the `workmanager` plugin, every 15 min with network) and every app open both process the queue, so summaries are ready even if you never open the app. |
| 5 | **No email in v1.** A local notification digest replaces it. |
| 6 | **Build the real edge first.** The edge is Save → AI summary; Digital Wellbeing and reel blockers already count. So **Phase 1 is manual Share → Reel Bot → summary**, and the counter comes after. **Checkpoint after Phase 1:** if you aren't using it every day for a week, stop. |
| 7 | **Manual Share is the only Save flow.** The bubble and its auto-Save (Phase 3) shipped in v0.3.0 and were removed in v0.9.0: no overlay, no tapping inside Instagram. |

## 3. Feasibility by feature

| Feature | Feasible? | How | Main risk |
|---|---|---|---|
| Save by Share | **Yes** | Share → **Reel Bot** in the system share sheet. The URL arrives as a normal `ACTION_SEND` intent | None significant; Instagram needs an extra "Share to…" tap |
| YouTube Shorts | **Easy** | Pass the public URL straight to Gemini as `file_data`; nothing is downloaded. If Gemini rejects it, YouTube's keyless oEmbed gives title, channel and thumbnail for a caption+thumbnail summary | [Certain] Doesn't work for private or unlisted videos. [Certain] Free tier: 8 h of YouTube video per day |
| Instagram media | **Yes, mostly** | A logged-out cascade run **on the phone** (see §3.2): embed page → post page JSON → logged-out GraphQL → web GraphQL → oEmbed metadata → Apify if the user has a key → caption + thumbnail | [Likely] Instagram changes its page JSON and query ids every few months, so each step can break; the cascade means one break isn't fatal. [Certain] CDN links expire within hours |
| Posts (images/carousels) | Yes | Images go to any vision model | None significant |
| Background analysis | Yes | `workmanager` plugin runs the Dart pipeline in a background isolate | [Likely] OEM battery killers delay it; app open still catches up |
| Count reels/shorts | **Yes, fragile, optional** | A Kotlin `AccessibilityService` counts **distinct reels**: a fingerprint of each reel's screen text, counted once it has been on screen ≥ 1.5 s, once per day | [Likely] Instagram and YouTube change their view ids with updates. Mitigated by an "unknown" alert (§4.1) |
| Time spent | Yes | Time in Instagram and YouTube from `UsageStatsManager` events (Usage access, no Accessibility); the optional counter adds time on the Reels/Shorts screens | It is time in the whole app, not only Reels; events are kept by Android for about a week, so older days may show less |
| Bubble / auto-Save | **Removed (v0.9.0)** | Was a `TYPE_ACCESSIBILITY_OVERLAY` bubble with an automated Share | Not wanted: saving is Share → Reel Bot only |
| Photos and screenshots | Yes (v0.8.0) | Shared `image/*` (one or several) is shrunk to ≤ 1280 px and sent as an image | None significant |
| Gemini / OpenAI / Anthropic | **All three** (v0.5.0) | [Certain] Gemini takes video and audio natively. OpenAI and Claude get 6 frames (no audio) or the images | Each provider is a separate request shape |
| Chat over notes | Yes (v0.5.0) | Keyword-matched notes go into the prompt of the chosen provider (Gemini, OpenAI, Claude, Groq) | Keyword overlap, not embeddings |
| "Container inside the phone" | **No** | [Certain] Android can't run Docker without root | — |
| End-of-day email | **Not in v1** | Notification instead | [Certain] App passwords need 2-Step Verification |

### 3.1 What open-source projects do

About 30 projects were read (full table: [RESEARCH.md](RESEARCH.md)). In short:
- **YouTube:** every downloader (yt-dlp, NewPipe, YouTube.js, Invidious, Seal…) fights PO tokens and signatures. Our URL → Gemini path skips all of it, so it stays.
- **Instagram:** the long-lived projects (cobalt, InstaFix-Revived, yt-dlp) try several **logged-out** routes and fall through on failure. The query ids (`doc_id`) rotate every few months; four different ones appear across projects.
- **The best workflow** combines InstaFix-Revived's order and safeguards (embed page first, negative cache, ids as config), yt-dlp's current logged-out query, and InstaDownload's on-device approach, run in a WebView instead of faking a browser. See the cascade in §3.2 and every request in [ENDPOINTS.md](ENDPOINTS.md).

### 3.2 The Instagram cascade

Cheapest first; stop at the first step that yields a video URL. Steps 1 and 5 are plain HTTPS; steps 2–4 run inside a hidden WebView (real Chrome, honest user agent, own cookie jar).

| # | Step | Endpoint ([ENDPOINTS.md](ENDPOINTS.md)) | Source of the idea |
|---|---|---|---|
| 1 | Embed page `contextJSON` → `video_url` | `IG-EMBED` | InstaFix, InstaFix-Revived, cobalt |
| 2 | Post page `data-sjs` JSON → `video_versions` (the page load that steps 3–4 reuse) | `IG-POST-PAGE` | yt-dlp fallback, InstaDownload |
| 3 | Logged-out post GraphQL (`media_id`) | `IG-GQL-LOGGEDOUT` | yt-dlp, totallynotdavid/downloader |
| 4 | Web post GraphQL (`shortcode`) | `IG-GQL-WEB` | InstaFix-Revived, cobalt |
| 5 | oEmbed → title, author, thumbnail (no video) | `IG-OEMBED` | InstaFix-Revived, cobalt |
| 6 | Apify, only with the user's key | `APIFY-RUN` | old Reel Brain code |
| 7 | Caption + thumbnail summary | — | — |

Around the cascade: one fetch per post at a time, a 1 h negative cache for posts that are private/deleted, a 30 min pause after a 429 or a login redirect, and the winning step recorded per item.

## 4. Uncomfortable truths

1. **Detection breaks silently.** [Likely] An Instagram/YouTube update can rename the view ids, and the count drops to zero with no error. So: capture the real ids on your phone **before** writing the rules, and alert when the share of `unknown` reels jumps (≥ 5 unknown and ≥ 30% of today's total).
2. **Count reels, not swipes.** [Likely] Debounced scroll events also count swipe-backs, half-swipes and refreshes. Test sloppily.
3. **Caption-less reels collide.** [Likely] A fingerprint of author + caption makes two caption-less reels from one creator look identical. When caption, audio and title are all blank, the like count (bucketed to 2 significant figures) is added to the fingerprint. [Guessing] Rare boundary flips (999 → 1K) can still double-count.
4. **Instagram fetching is an arms race.** [Likely] The logged-out page JSON and GraphQL `doc_id`s change every few months (yt-dlp and cobalt ship fixes regularly). The cascade keeps working while one step is broken, the debug screen shows which step succeeded per item, and when all video steps fail the item still gets a caption + thumbnail summary (`analysis = "caption+thumbnail"`), not a failure. Private and age-restricted posts never work logged out.
5. **No backend means no backup.** [Certain] Uninstalling the app or clearing its storage deletes the library. Export/Import is part of Phase 1.
6. **Installing is hard for friends.** [Certain] Android 13+ needs *Allow restricted settings* before Accessibility can be turned on. [Likely] Play Protect's India fraud protection can block an APK that asks for Accessibility; Indian OEM phones (Xiaomi, Realme, Oppo, Vivo) need Autostart and battery exemption. Developer verification for sideloaded apps arrives in 2027 [Guessing on dates]. Hence v1 is your phone only, and `docs/INSTALL.md` (screenshots of each step) comes before sharing.
7. **One copy of SQLite per database file.** [Likely] Dart's `sqlite3` bundles its own SQLite; if Kotlin and Dart both open one file, their locks can clash. **Kotlin owns `counter.db`** (counts and `pending_items`); Dart reaches it only through the `reelbot/counter` channel. Dart owns the library DB (`reel_brain.db`).

## 5. Things to avoid

- Logging in to Instagram, or instaloader/instagrapi. That gets accounts banned.
- Downloading YouTube files. Use Gemini's URL input.
- Auto-analysing every watched reel. Only saved ones.
- The clipboard hack. It overwrites your clipboard and fails silently on some phones.
- Automation beyond Save: no auto-scroll, likes, follows or opening profiles.
- Containers, a bundled Python runtime, Tesseract.
- Any backend. Hard-coding your own keys in the APK.
- MediaProjection screen capture.
- Storing a CDN video URL and downloading it later. Download in the same run that finds it.
- Faking a Googlebot (or any crawler) user agent to get past Instagram's login wall.
- Copying code from AGPL/GPL projects (cobalt, gallery-dl, Seal, NewPipe) into the app. Reimplement the approach. Only Unlicense/MIT code (yt-dlp, InstaFix, InstaFix-Revived) may be copied, with attribution; InstaDownload is GPL-3.0.

---

## 6. Build order

### Phase 1: Share → summary (1–2 weeks)
- Recover the old app from git history and strip the server parts.
- Kotlin: transparent share receiver (`ACTION_SEND`), `pending_items` in `counter.db`, and the `reelbot/counter` channel as a plugin (so background isolates can use it).
- Dart: the analysis pipeline, run by the `workmanager` background task and on app open.
  - **YouTube:** URL straight to Gemini; oEmbed caption+thumbnail if Gemini rejects it.
  - **Instagram:** Kotlin `InstagramFetcher` runs the §3.2 cascade. The video is downloaded in the same run and sent to Gemini.
- Library, search, *Ask your library*, Export/Import.
- **Exit test:** share 10 reels and 10 Shorts without opening the app; within 30 min all 20 have summaries. Then use it daily for a week (the checkpoint).

### Phase 2: Counter (1–2 weeks)
- **First, capture:** ship the service with only the debug capture, open Reels and Shorts on your phone, copy the real view ids, then write `DetectionRules`.
- Tracker (fingerprint + dwell + per-day dedupe, like-count signal for caption-less reels), Today, History, setup checklist, debug screen, unknown alert.
- **Exit test (sloppy use):** 20 reels + 20 shorts, including 5 swipe-backs, 3 half-swipes, 1 refresh, 2 rewatches and 3 caption-less reels from one creator. Count within ±1.

### Phase 3: Bubble + optional auto-Save (removed)
- Shipped in v0.3.0 and **removed in v0.9.0** at the user's request, before its 90% exit test was run. Manual Share is the only Save flow.

### Phase 4: Daily digest
- Kotlin `WorkManager` job around 21:30. If the app wasn't opened today, post one notification: "37 reels · 52 min · 3 saved: A, B, C". Titles come from items the background job already analysed; with none, counts only.

### Built after Phase 4 (v0.5.0–v0.9.4)
Other providers (OpenAI, Claude, Groq for chat) and several Gemini keys in turn; chat as the home tab with saved chats; photos, Instagram posts and carousels; the Insights tab; seen/unseen and a 3-day archive; richer notes (overview, detail, mentions) with Re-analyse; Export/Import including chats; an update banner. See [STATUS.md](STATUS.md) for the full list.

### Before sharing with friends
- [INSTALL.md](INSTALL.md) is written (v0.9.4); it still needs one screenshot per step (download, Play Protect, restricted settings, Accessibility, battery, Autostart, Gemini key).

### Later, only if people actually use it
Email or weekly digest, remote updates to the detection rules, on-device transcription.

## 7. Verification

- **Phase 1:** share 10 reels + 10 Shorts with the app closed; check summaries arrive in the background. Record which step succeeded per item (§3.2 steps 1–7); the target is ≥ 80% of public reels getting the **video** without Apify. Below that, fix the failing step before building Phase 2. Export, wipe app data, Import, check the library comes back.
- **Phase 2:** run the sloppy-use test on a stock phone and a Xiaomi or Realme. Rename one id in the rules on purpose and check the unknown alert fires. Kill the app, reboot, and confirm counting continues.
- **Phase 4:** force-run the worker (`adb shell cmd jobscheduler run -f <pkg> <id>`) and check the notification, with and without analysed items.

## Sources

- [Google Play: Accessibility API policy](https://support.google.com/googleplay/android-developer/answer/10964491)
- [Gemini API: video understanding (YouTube URLs)](https://ai.google.dev/gemini-api/docs/video-understanding)
- [cobalt: Instagram service](https://github.com/imputnet/cobalt/blob/main/api/src/processing/services/instagram.js)
- [yt-dlp: Instagram extractor](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/instagram.py)
- [InstaDownload (Kotlin, GPL-3.0)](https://github.com/Orang-Studio/InstaDownload) · [F-Droid listing](https://f-droid.org/packages/com.vakarux.instadownload/)
- [gallery-dl: Instagram extractor](https://github.com/mikf/gallery-dl/blob/master/gallery_dl/extractor/instagram.py)
- [Seal (yt-dlp on Android)](https://github.com/JunkFood02/Seal)
- Full survey with links: [RESEARCH.md](RESEARCH.md)
- [Google: enhanced fraud protection pilot in India](https://blog.google/intl/en-in/products/launching-enhanced-fraud-protection-pilot-in-india/)
- [Android developer verification](https://support.google.com/android-developer-console/answer/16561738)
- [Android sideloading changes timeline](https://www.androidauthority.com/android-sideloading-changes-timeline-3679204/)
