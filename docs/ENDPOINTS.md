# Reel Analyser: endpoint reference

Every network call and every app-internal interface, in one place. **Update this file in the same commit as any change to a request** (see [RELEASES.md](RELEASES.md) §2). Each endpoint lists the tests that cover it ([TESTS.md](TESTS.md)).

**Last verified:** 5 Nov 2026, against open-source code (see [RESEARCH.md](RESEARCH.md)). Not yet called from a real phone; the `T-LIVE-*` tests do that.

Card format:
- **ID**, **phase**, **owner** (the file that makes the call)
- **Request**: method, URL, auth, headers, body
- **Use**: the response fields we read
- **Fails when** → what we do
- **Tests**, **source**

---

## 1. Instagram: cascade overview

Order and rationale: [PLAN.md](PLAN.md) §3.2. Owner of all `IG-*` calls: `mobile/packages/reelbot_native/android/src/main/kotlin/app/reelbrain/InstagramFetcher.kt` (rules in `IgCascade.kt`, parsers in `IgParse.kt`).

Shared values:
- `code`: the shortcode from `instagram.com/(reel|reels|p|tv)/<code>`.
- `mediaId`: `code` decoded as base-64, alphabet `A–Z a–z 0–9 - _`, most-significant first (`T-IG-U01`).
- `IG_APP_ID` = `936619743392459` (web app id; same in yt-dlp, cobalt, InstaDownload, totallynotdavid).
- Query ids live in `res/raw/ig_queries.json`, never in code:

```json
{
  "loggedOutPost": {"name": "PolarisLoggedOutDesktopWWWPostRootContentQuery", "docId": "27130156389949648", "verified": "2026-10-29"},
  "webPost":       {"name": "PolarisPostActionLoadPostQueryQuery",          "docId": "25531498899829322", "verified": "2026-11-02"}
}
```

A rediscovered id (`IG-JS-BUNDLE`) is cached in SharedPreferences `ig_queries` and wins over the bundled file until it fails.

Rules for every `IG-*` call:
- Never log in; never send the Instagram app's cookies (the WebView's `CookieManager` is separate).
- At most one Instagram request every 5 s; one fetch per post at a time.
- `429`, or a redirect to `/accounts/login`, or `{"require_login": true}` → stop all `IG-*` calls for 30 min, item stays `queued`.
- A post that is private, deleted or age-restricted → negative cache 1 h for that `code`.

---

## 2. Instagram endpoints

### IG-EMBED: embed page
- **Phase** 1 · **cascade step** 1 · plain HTTPS (OkHttp)
- **Request:** `GET https://www.instagram.com/p/{code}/embed/captioned/`
  - Headers: `User-Agent` = the WebView's default UA (`WebSettings.getDefaultUserAgent`), `Accept: text/html`, `Accept-Language: en-US,en;q=0.9`.
  - No auth, no cookies.
- **Use:** regex `"init",\[\],\[(.*?)\]\],` → JSON → `contextJSON` (a JSON string) → `gql_data.shortcode_media` (or `.xdt_shortcode_media`):
  - `video_url`, `is_video`, `display_url`
  - `edge_media_to_caption.edges[0].node.text` (caption)
  - `owner.username`
  - `edge_sidecar_to_children` for carousels
- **Fails when:** non-200; no `contextJSON`; `gql_data` null (common: Instagram often omits it for reels) → step 2.
- **Retries:** 2 extra tries, 1 s apart, on network errors only.
- **Tests:** `T-IG-F01`, `T-IG-F02`, `T-LIVE-01`
- **Source:** InstaFix `handlers/scraper`, InstaFix-Revived `data.go`, cobalt `requestHTML`.

### IG-POST-PAGE: post page JSON
- **Phase** 1 · **cascade step** 2 · hidden WebView
- **Request:** WebView `loadUrl("https://www.instagram.com/reel/{code}/")`. JavaScript on, images off, default UA.
- **Use:** in `onPageFinished`, `evaluateJavascript` returns the text of every `<script data-sjs>` (and `<script type="application/json">`) tag. Walk the JSON for an object with `pk` or `id` == `mediaId` that has `video_versions`, `carousel_media` or `image_versions2`; commonly at `…xig_polaris_media.if_not_gated_logged_out`. Read:
  - `video_versions[]` (`url`, `width`, `height`): pick the smallest with width ≥ 480
  - `image_versions2.candidates[0].url` (thumbnail)
  - `caption.text`, `user.username`, `video_duration`
  - `carousel_media[]` for carousels
  - Also capture for steps 3–4: the LSD token (`["LSD",[],{"token":"…"}`), and `csrftoken` from `CookieManager`.
- **Fails when:** final URL path starts with `/accounts/login` → rate-limit rule (§1); no matching object → step 3 (same page stays loaded).
- **Timeout:** 20 s.
- **Tests:** `T-IG-F03`, `T-IG-F04`, `T-LIVE-02`
- **Source:** yt-dlp `InstagramIE._real_extract` fallback, InstaDownload `tryPostPage` (ideas only, GPL).

### IG-GQL-LOGGEDOUT: logged-out post query
- **Phase** 1 · **cascade step** 3 · `fetch()` inside the loaded post page (same origin)
- **Request:** `POST https://www.instagram.com/api/graphql`
  - Headers: `Content-Type: application/x-www-form-urlencoded`, `X-IG-App-ID: {IG_APP_ID}`, `X-FB-LSD: {lsd}`, `X-CSRFToken: {csrftoken}`, `X-FB-Friendly-Name: {loggedOutPost.name}`, `X-ASBD-ID: 359341`, `X-Requested-With: XMLHttpRequest`. Cookies: the WebView's own.
  - Body: `lsd={lsd}&fb_api_caller_class=RelayModern&fb_api_req_friendly_name={loggedOutPost.name}&server_timestamps=true&variables={"media_id":"{mediaId}"}&doc_id={loggedOutPost.docId}`
- **Use:** `data.xig_polaris_media.if_not_gated_logged_out` → same fields as IG-POST-PAGE.
- **Fails when:** `status: "fail"` with `require_login` → rate-limit rule; no `data` or an error mentioning the document → **stale query**: run `IG-JS-BUNDLE` once, retry once with the new id, else step 4.
- **Tests:** `T-IG-F05`, `T-IG-F06`, `T-LIVE-03`
- **Source:** yt-dlp (primary method), totallynotdavid/downloader `instagram-graphql.ts`.

### IG-GQL-WEB: web post query
- **Phase** 1 · **cascade step** 4 · `fetch()` inside the loaded post page
- **Request:** `POST https://www.instagram.com/graphql/query/`
  - Headers: as IG-GQL-LOGGEDOUT with `X-FB-Friendly-Name: {webPost.name}`.
  - Body: `lsd`, `fb_api_caller_class=RelayModern`, `fb_api_req_friendly_name={webPost.name}`, `server_timestamps=true`, `variables={"shortcode":"{code}","fetch_tagged_user_count":null,"hoisted_comment_id":null,"hoisted_reply_id":null}`, `doc_id={webPost.docId}`.
- **Use:** `data.xdt_shortcode_media` (or `data.shortcode_media`): `video_url`, `display_url`, `edge_media_to_caption`, `owner.username`, `edge_sidecar_to_children`.
- **Fails when:** `data.xdt_shortcode_media` is null → step 5; stale query → as IG-GQL-LOGGEDOUT.
- **Tests:** `T-IG-F07`, `T-LIVE-04`
- **Source:** InstaFix-Revived `data.go` (`doc_id 25531498899829322`), cobalt `requestGQL`, InstaFix.

### IG-OEMBED: metadata only
- **Phase** 1 · **cascade step** 5 · plain HTTPS
- **Request:** `GET https://www.instagram.com/api/v1/oembed/?url=https://www.instagram.com/reel/{code}/`, header `X-IG-App-ID: {IG_APP_ID}`.
- **Use:** `title` (caption), `author_name`, `thumbnail_url`, `media_id`. No video.
- **Fails when:** non-200 → step 6 with whatever earlier steps found.
- **Tests:** `T-IG-F08`, `T-LIVE-05`
- **Source:** InstaFix-Revived `enrichPublicOEmbedMetadata`, cobalt `getMediaId`.

### IG-JS-BUNDLE: rediscover a query id
- **Phase** 1 · only on a stale-query error, at most once per day per query
- **Request:** for each `https://static.cdninstagram.com/rsrc.php/…js` URL referenced by the loaded post page (newest first), `GET` it.
- **Use:** regex `"{name}_instagramRelayOperation",\[\],\(function\([^)]*\)\{\w+\.exports="(\d+)"` → new `docId`. Save to SharedPreferences with today's date.
- **Fails when:** not found in any bundle → keep the bundled id; debug screen shows "query id stale".
- **Tests:** `T-IG-F09`
- **Source:** InstaDownload `discoverProfileQuery` (idea only, GPL).

### IG-CDN: download the video
- **Phase** 1 · plain HTTPS, **in the same run** as the step that found the URL
- **Request:** `GET {video_url}` (hosts `*.cdninstagram.com`, `*.fbcdn.net`), headers `Referer: https://www.instagram.com/`, same UA. Write to `cacheDir/ig/{code}.mp4`.
- **Limits:** stop above 100 MB. URLs carry an `oe=` expiry (hex Unix time); never store them.
- **Fails when:** 403 (expired/signed) → rerun the cascade once; else continue without video.
- **Tests:** `T-IG-U03`, `T-LIVE-06`

---

## 3. Third-party APIs

### APIFY-RUN: Apify Instagram scraper (optional)
- **Phase** 1 · **cascade step** 6 · only if the user saved an Apify key · owner `lib/pipeline/apify.dart`
- **Request:** `POST https://api.apify.com/v2/acts/apify~instagram-scraper/run-sync-get-dataset-items?timeout=120`
  - Header `Authorization: Bearer {apifyKey}` (never in the query string), `Content-Type: application/json`.
  - Body: `{"directUrls": ["https://www.instagram.com/p/{code}/"], "resultsType": "posts", "resultsLimit": 1}`
- **Use:** first item: `videoUrl`, `displayUrl`, `images[]`, `childPosts[].videoUrl`, `caption`, `ownerUsername`, `timestamp`.
- **Cost:** ~$0.0023 per reel (measured in the old Reel Brain project).
- **Fails when:** 401/403 → tell the user the key is wrong; 402 → out of credit; timeout → step 7.
- **Tests:** `T-PIPE-05`, `T-LIVE-07`
- **Source:** old `fetchers/apify.py` (commit `5f0c001`).

### GEM-GENERATE: Gemini analysis
- **Phase** 1 · owner `lib/pipeline/gemini.dart`
- **Request:** `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
  - Header `x-goog-api-key: {geminiKey}`, `Content-Type: application/json`.
  - Body parts, one of:
    - YouTube: `{"fileData": {"fileUri": "https://www.youtube.com/shorts/{id}", "mimeType": "video/*"}}`
    - Instagram video ≤ 20 MB: `{"inlineData": {"mimeType": "video/mp4", "data": "<base64>"}}`
    - Larger video: `{"fileData": {"fileUri": "{uploaded.uri}", "mimeType": "video/mp4"}}` (from GEM-UPLOAD)
    - Caption + thumbnail: the thumbnail as `inlineData` `image/jpeg` + a text part with author, caption, on-screen text
  - Plus the analysis prompt and `generationConfig.responseSchema` (the shared analysis spec from the old app).
- **Models:** `gemini-3.5-flash` first, then `gemini-3.5-flash-lite` (old app's order); remember the thinking level each model accepts.
- **Fails when:** 400 → next thinking level / model; 429 → item stays `queued`; 5xx → stays `queued`; YouTube URL rejected (private, unlisted, 8 h/day free cap) → `YT-OEMBED`.
- **Tests:** `T-PIPE-01`…`T-PIPE-04`, `T-PIPE-06`, `T-LIVE-08`

### GEM-UPLOAD / GEM-FILE-GET / GEM-FILE-DELETE: Gemini Files API
- **Phase** 1 · owner `lib/pipeline/gemini.dart` · only for videos > 20 MB
- **Start:** `POST https://generativelanguage.googleapis.com/upload/v1beta/files` with `x-goog-api-key`, `X-Goog-Upload-Protocol: resumable`, `X-Goog-Upload-Command: start`, `X-Goog-Upload-Header-Content-Length`, `X-Goog-Upload-Header-Content-Type`, body `{"file": {"display_name": "{code}"}}` → header `x-goog-upload-url`.
- **Upload:** `POST {x-goog-upload-url}` with `X-Goog-Upload-Offset: 0`, `X-Goog-Upload-Command: upload, finalize`, body = bytes → `file.name`, `file.uri`, `file.state`.
- **Poll:** `GET https://generativelanguage.googleapis.com/v1beta/{file.name}` every 2 s until `state == "ACTIVE"` (max 120 s); `FAILED` → caption+thumbnail.
- **Delete:** `DELETE https://generativelanguage.googleapis.com/v1beta/{file.name}` after analysis (files also expire after 48 h).
- **Tests:** `T-PIPE-07`

### YT-OEMBED: YouTube metadata fallback
- **Phase** 1 · owner `lib/pipeline/runner.dart`
- **Request:** `GET https://www.youtube.com/oembed?url={shortsUrl}&format=json` (no key).
- **Use:** `title`, `author_name`, `thumbnail_url` → caption+thumbnail analysis.
- **Fails when:** 401/404 (private or removed) → `failed`.
- **Tests:** `T-PIPE-02`, `T-LIVE-09`

### GH-RELEASE-LATEST: update check
- **Phase** "before friends" ([PLAN.md](PLAN.md) §6) · owner `lib/data/update_check.dart` (v0.9.4)
- **Request:** `GET https://api.github.com/repos/nevil-sanish/reel-analyser/releases?per_page=1`, header `Accept: application/vnd.github+json`. No token. At most once a day (`KeyStore.updateCheckedAt`). Not `/releases/latest`: it skips pre-releases and every release so far is one (404).
- **Use:** `tag_name` (compare with the app's `versionName`), `html_url`, the asset whose name ends in `.apk`.
- **Fails when:** 403 rate limit (60/h per IP) or offline → silently skip.
- **Tests:** `T-REL-01`

---

## 4. App-internal interfaces

### SHARE-IN: share intent
- **Phase** 1 · owner `ShareReceiverActivity.kt`
- `Intent.ACTION_SEND`, `type text/plain`, `EXTRA_TEXT` contains the URL (Instagram adds text around it; YouTube sends `https://youtube.com/shorts/{id}?si=…`).
- Accepted URLs: `instagram.com/(reel|reels|p|tv)/{code}`, `youtube.com/shorts/{id}`, `youtu.be/{id}`. Tracking params (`igsh`, `si`) stripped.
- v0.8.0: also `ACTION_SEND` with `image/*` (`EXTRA_STREAM`): copied into app storage and queued as `photo:<path>`.
- v0.9.4: also `ACTION_SEND_MULTIPLE` with `image/*`: each image becomes its own `photo:` item (file names `<time + n>.jpg`).
- **Tests:** `T-SHARE-01`…`T-SHARE-04`

### IG-EMBED-PLAYER: cascade step 2 (v0.6.2)
- Owner `InstagramFetcher.playerStep`. Loads `https://www.instagram.com/reel/{code}/embed/captioned/` in a hidden WebView with autoplay allowed, presses play, and waits up to 8 s for the `<video>` element's https src. Any `.mp4` request to `cdninstagram.com` / `fbcdn.net` seen by `shouldInterceptRequest` is the backup, with `bytestart`/`byteend` stripped to get the whole file. Also reads the poster, `.UsernameText` and `.Caption` (username prefix and "View all … comments" removed).
- From v0.6.2 the cascade is: 1 embed HTML, **2 embed player**, 3 post page, 4 GraphQL logged-out, 5 GraphQL web, 6 oEmbed, 7 Apify (Dart).
- **Tests:** `T-IG-F12`

### OPENAI-CHAT, CLAUDE-MESSAGES, GROQ-CHAT: other AI providers (v0.5.0)
- Owner `lib/pipeline/providers.dart` (`ChatModel`). Raw HTTP; keys from Settings.
- **OpenAI** `POST https://api.openai.com/v1/chat/completions`, `gpt-6-luna` (v0.6.0; was `gpt-6.1-terra`), `reasoning_effort: none`, images as `image_url` data URLs with `detail: low`.
- **Claude** `POST https://api.anthropic.com/v1/messages`, `claude-haiku-5-5` (v0.6.0; was `claude-opus-5-5`), headers `x-api-key`, `anthropic-version: 2026-10-21`; body `thinking: disabled`, `output_config.effort: low` (Haiku has no server-side fallback); a `refusal` stop reason counts as rejected.
- **Groq** `POST https://api.groq.com/openai/v1/chat/completions`, `openai/gpt-oss-20b` with `reasoning_effort: low` (v0.6.0; Groq lists the Llama models as Contact Sales). Chat only.
- Notes: OpenAI and Claude get 6 frames (`videoFrames`) or the thumbnail, never audio, and only when Gemini has no key or every Gemini key is rate-limited or rejected. 401/403 → bad key, 429/5xx/network → retry later.
- Chat sends the notes that match the question's words: the best 8 in full, the next 32 as title + summary; a question with no matches gets every title + summary. Plus the last 10 turns.
- **Tests:** `T-PIPE-12`

### FEEDBACK: GitHub issue (v0.5.0)
- Settings → Send feedback opens `https://github.com/nevil-sanish/reel-analyser/issues/new?title=Feedback&body=…` in the browser with only the typed text and the app version. The user submits it on GitHub. Nothing else leaves the phone except reels the user shares to an AI provider.

### CH-COUNTER: method channel `reelbot/counter`
- Owner `CounterPlugin.kt` (Kotlin) and `lib/native/counter_bridge.dart` (Dart). Registered as a plugin, so it exists in background engines too.

| Method | Phase | Args | Returns | Tests |
|---|---|---|---|---|
| `pendingItems` | 1 | `{status}` | `List<{id,url,app,author,caption,onScreenText,createdAt,status}>` | `T-CH-01` |
| `setPendingStatus` | 1 | `{id, status, title}` (`title` from v0.4.0, for the digest) | `null` | `T-CH-01` |
| `markOpened` | 4 | — | `null` (writes `last_opened`) | `T-DIG-02` |
| `fetchInstagram` | 1 | `{url}` | `{step, author, caption, thumbnailUrl, videoPath, images}` (`images` from v0.8.0); error `rate_limited` | `T-CH-02` |
| `saveDownload` | 1 | `{name, text}` | `null` (writes `Downloads/ReelBot/<name>`) | manual `T-MAN-01` |
| `videoFrames` | 5 | `{path, count}` | `List<Uint8List>` 512 px JPEGs, evenly spaced | `T-PIPE-12` (faked) |
| `openUrl` | 5 | `{url}` | `null` (ACTION_VIEW) | manual |
| `sweepPhotos` | 9 | `{keep}` | `null` (deletes `files/photos/*` not in `keep`) | manual |
| `notifyNotes` | 6 | `{title, text}` | `null` ("note ready" notification after a background run) | manual |
| `daily` | 2 | `{days}` | `List<{date,app,reels,ms,unknown}>` | `T-CH-03` |
| `hourly` | 8 | `{days}` | `List<{hour, reels, ms}>` by local hour of `first_seen` | `T-UI-03` (helpers) |
| `seenItems` | 2 | `{date}` | `List<{app,fp,firstSeen,dwellMs,author,caption}>` | `T-CH-03` |
| `debugState` | 2 | — | `List<{k,v,ts}>` | `T-CH-03` |
| `setCapture` | 2 | `{on}` | `null` | `T-CH-03` |
| `setAutoSave` | 3 | `{on}` | `null`; `status` also returns `autoSave` | manual `T-SAVE-02` |
| `status` | 2 | — | `{serviceEnabled,serviceRunning,batteryExempt,notificationsAllowed,sdkInt,manufacturer,capture}` | `T-CH-04` |
| `openAccessibilitySettings`, `openAppInfo`, `openNotificationSettings`, `requestBatteryExemption`, `openAutostart` | 2 | — | `null` (start an activity) | manual `T-MAN-04` |

### WM-ANALYSE: background analysis task
- `workmanager` periodic task `analyse`, every 15 min, network required, `existingWorkPolicy: keep`. Entry `callbackDispatcher` in `lib/pipeline/background.dart`.
- **Tests:** `T-BG-01`, `T-BG-02`

### WM-DIGEST: daily digest worker
- Kotlin `DigestWorker`, unique periodic work `reelbot_digest`, hourly; posts once after 21:00 if the app wasn't opened today. Phase 4.
- **Tests:** `T-DIG-01`, `T-DIG-02`

---

## 5. Change log

| Date | Change |
|---|---|
| 2026-11-05 | First version, from the open-source survey. |
| 2026-11-05 | v0.1.0: implemented IG-EMBED…IG-CDN, APIFY-RUN, GEM-*, YT-OEMBED, SHARE-IN, CH-COUNTER (+ `saveDownload`), WM-ANALYSE. Kotlin moved to the `reelbot_native` plugin (IMPLEMENTATION §0.1). Not yet verified from a phone (`T-LIVE-*`). |
| 2026-11-06 | v0.2.0: implemented the Phase 2 CH-COUNTER methods, plus `openNotificationSettings` (the plugin has no activity to ask for `POST_NOTIFICATIONS` itself). |
| 2026-11-06 | v0.3.0: `setAutoSave` and `status.autoSave` for the experimental auto-Save. |
| 2026-11-06 | v0.4.0: WM-DIGEST implemented; `setPendingStatus` takes `title`; `markOpened` added. |
| 2026-11-06 | v0.5.0: GEM-GENERATE uses `gemini-3.6-flash` (3.5 Flash now routes there), YouTube as a `watch?v=` URL with no mimeType, `videoMetadata.fps` 0.5, `thinkingLevel` minimal and low media resolution on the first attempt. New: OPENAI-CHAT, CLAUDE-MESSAGES, GROQ-CHAT, `videoFrames`, `openUrl` (feedback). |
| 2026-11-06 | v0.6.0: cheaper models first to save tokens: Gemini `gemini-3.5-flash-lite` then `gemini-3.6-flash`; OpenAI `gpt-6-luna`; Claude `claude-haiku-5-5`; Groq `openai/gpt-oss-20b`. Chat sends only matching notes. Chat picks provider and model (cheapest default, one stronger option each: `gemini-3.6-flash`, `gpt-6.1-terra`, `claude-sonnet-5-5`, `openai/gpt-oss-120b`). `notifyNotes` added. |
| 2026-11-06 | v0.6.2: IG-EMBED-PLAYER added as cascade step 2; later steps renumbered (Apify now 7). |
| 2026-11-06 | v0.8.0: SHARE-IN takes images; `fetchInstagram` returns `images` (post and carousel stills). |
| 2026-11-06 | v0.8.1: `hourly` added for Insights. |
| 2026-11-06 | v0.9.3: `sweepPhotos` added. |
| 2026-11-06 | v0.9.4: GH-RELEASE-LATEST implemented (via `/releases`, see above); SHARE-IN takes `ACTION_SEND_MULTIPLE`. |

## 9. Daily goals (full build only)

Owner: `mobile/lib/full/goals.dart` (`GoalFetcher`, `HandleChangeJudge`). None of these exists in the semi build (`tool/check_apks.sh` proves it). Only the public username leaves the phone; no key, token or cookie.

| ID | Request | Use | Fails when |
|---|---|---|---|
| GOAL-GH | `GET https://api.github.com/search/commits?q=author:<user> author-date:<start>..<end>&per_page=1` | `total_count`, `incomplete_results`: commits in public repositories that day | 403/429: retry later; 422: unknown user |
| GOAL-CF | `GET https://codeforces.com/api/user.status?handle=<h>&from=1&count=100` | different problems with verdict `OK` that day | `status != OK`: "not found" or retry later |
| GOAL-LC | `POST https://leetcode.com/graphql` (`matchedUser`, `recentAcSubmissionList(limit 20)`) | different `titleSlug` that day. Unofficial; may stop working | null `matchedUser`: unknown user |
| GOAL-AI | the user's own AI provider (first with a key; cheapest model), one message: old and new username and the typed reason | JSON `{valid, reason}`; only `valid: true` allows a username change | no key, error or malformed answer: no change (fail closed). The reason is not stored |

Schedule: a WorkManager one-off task for the next 00:20 local time (named `goals-<date>`, re-booked each run), the 15-minute `analyse` task and opening the app as fallbacks. Tests: `mobile/test/full/goals_test.dart`.
