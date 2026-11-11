# Reel Analyser

Android app that turns the Instagram Reels, YouTube Shorts, Instagram posts and photos you share to it into short AI notes you can search and chat with, counts how many reels and shorts you watch, and (full build, optional) can block Reels and Shorts once you pass a limit you set. It uses your own AI keys. There is no account and no server: everything lives on your phone.

**Download:** [latest APK](https://github.com/nevil-sanish/reel-analyser/releases) (Android 10+).

## Look and feel

A classic Greek look, in warm marble white and gold, or charcoal and gold in the dark: serif titles, hairline gold edges, a Greek key as the one ornament. It runs light on phones (no blur, a still background), moves with short springs and fades, and gives a light vibration on taps and results. Settings has switches for Vibration and Reduce motion. The launcher icon is drawn by `mobile/tool/make_icon.py`.

## How it works

### 1. Save: share anything to Reel Analyser

```
Instagram / YouTube / Gallery ──Share──▶ Reel Analyser ──▶ "Saved ✓" (you stay where you were)
                                            │
                                            ▼
                                  queue on the phone (counter.db)
```

- **Reels, Shorts and Instagram posts:** tap **Share → Reel Analyser**. On Instagram, use *Share → Share to…*. The link is cleaned of tracking codes and queued.
- **Photos and screenshots:** share one or several from any app. Each picture is copied into the app, shrunk to 1280 px, and queued as its own note.
- That's the only way in: no floating button over the apps you watch.

### 2. Analyse: in the background, every 15 minutes and whenever you open the app

```
queued item ──▶ get the media ──▶ AI makes a note ──▶ Library  (+ "Note ready" notification)
```

| You shared | How Reel Analyser gets it | What the AI sees |
|---|---|---|
| YouTube Short | the link goes straight to Gemini | the whole video and its audio |
| Instagram reel | logged-out steps on your phone: embed page → embed player → post page → two web queries → oEmbed, then Apify if you added a token | the downloaded video, deleted after analysis |
| Instagram photo post / carousel | the same steps, collecting every image | up to 10 images in one request |
| Photo or screenshot | already on the phone | the picture |

If no video can be fetched, the note is made from the caption and thumbnail, and the note says so. Open **Show full analysis**, then **Try again with the video**.

**Which AI:**
- **Gemini** (free key) watches video. You can add several Gemini keys: each new reel uses the next key, and a reel moves to another key when one hits its limit. Cheapest model first: 3.5 Flash-Lite, then 3.6 Flash.
- **OpenAI** (GPT-6 Luna) and **Claude** (Haiku 5.5) are used when no Gemini key can take a reel. They see 6 frames from the video, without sound.
- **Groq** is for chat only.

Each note has a short bulleted overview in simple words that covers every important point, and behind *Show full analysis*: a fuller summary, every key point and step, and the tools, people and links mentioned.

### 3. Use: three tabs

- **Ask:** today's reels, shorts and minutes at the top, then a chat that answers only from your saved notes. Pick the provider and model from the chip above the ask bar. Every chat is saved; the clock icon reopens old ones.
- **Insights:** a Week or Month view of your watching: minutes per day, the hours you watch most, and your heaviest weekday.
- **Library:** every note, filterable by Reels, Shorts, Posts and Photos. A dot marks notes you haven't opened. Swipe left to delete, right to archive, or long-press to select several, then mark them read, archive or delete them; every one of these has Undo. Sharing a reel you already saved doesn't analyse it again: its note comes back to the top, unread. Notes you've read move to the Archive after 3 days.

### 4. Time and counts: Usage access, plus optional Accessibility

Both are optional; notes and chat work without them.

**Time in Instagram and YouTube** comes from Android's own app-usage data (Usage access). Nothing is read from the screen, and it's time in the whole app, not only Reels or Shorts.

**Counting reels and Shorts is optional.** It needs Android's Accessibility service **and** your separate OK inside the app (*Settings → Set up Insights → Allow reading the reel screens*, off by default). With both, Reel Analyser reads the Reels and Shorts screens to count what you watch and the time on those screens:
- a reel counts after 1.5 seconds on screen;
- swipe-backs and rewatches the same day don't count twice;
- it keeps only an anonymous fingerprint of each reel, never what it was;
- it never taps, types or scrolls.

After 9 pm, on days you didn't open the app, you get one digest notification.

### 5. Reel blocker (Full build only, optional)

*Settings → Reel blocker.* A self-control tool for your own phone: it blocks only Reels, Shorts and reel pages, never the rest of the app.

- **What to block:** Instagram Reels, YouTube Shorts and reel or shorts pages in a browser (`instagram.com/reels`, `youtube.com/shorts`). Pick any of them.
- **Limits:** one shared daily limit for everything you picked, or one for each, in minutes or hours. It counts time on reels only.
- **Schedule:** any number of time slots when reels are allowed (for example 18:00 to 19:00). Outside them they are blocked. A reel is watched only when both the limit and the slots allow it.
- **Block screen:** opens over the reel with a quote. Close works after 3 seconds.
- **Reels only or whole app:** for Instagram and YouTube you choose whether only reel time counts (and only reels are blocked) or all time in the app counts (and the whole app is blocked past the rule).
- **Locked rules:** after the first set-up, changing the rules takes a 50-word paragraph typed by hand (no paste), checked with your own AI key; an accepted change starts at the next 00:00.
- **Turn off for today:** needs a paragraph of at least 50 words typed by hand (no paste; typing very fast locks the field until you stop for 2 seconds). It is checked on the phone and then with your own AI key that it is a valid reason; it is not stored.
- **Remove for good:** needs a paragraph of at least 50 words typed by hand: no paste, not too fast, no typical AI wording, and a valid reason checked with your own AI key. These checks are best-effort.
- **History:** dates and kinds of limit hits and cancel attempts. No photos, no text.
- **It can be bypassed** (turn Accessibility off, change the clock, use another browser or app). It is a nudge for you, not a lock, and not for use on anyone else's phone.

### 6. Daily goals (Full build only, optional)

*LinkedIn (both builds).* Share a public LinkedIn post (text, pictures or video) to Reel Analyser. The app reads the post's public page without any login, removes the tracking part of the link, and analyses the video, the pictures or the text. Posts that need a login cannot be read.

*Library → Folders (both builds).* Make your own folders (the folder icon) or press **Organize** (the sparkle icon): your own AI key sorts every note into your folders first, then suggests new folders only for real topics shared by at least 3 notes, which you approve. Notes that fit nothing stay in All, which always has every note. New notes go into the folder their words clearly match when they are saved. Each folder has its own chat that answers only from that folder's notes. Long-press notes to move them; long-press a folder to rename or delete it. With no folders the Library looks as before.

*Blocker tab → Daily goals.* Set a daily number of GitHub commits, Codeforces problems and LeetCode problems. Each day is checked automatically just after midnight, from your public activity (only your username is sent). Miss a day and the whole Instagram app (and YouTube, if you pick it) is blocked the next day only; miss that day too and the day after is blocked as well. A day you could not be read is never counted as a miss.

- **Changing or stopping:** allowed any time, but after the first set-up it takes a typed paragraph of at least 50 words (no paste), checked with your own AI key that it is a valid reason. A running penalty still ends on its last day.
- **Locked usernames:** once used, a username cannot be changed freely. Ask, come back tomorrow, then type at least 50 words about why; your own AI provider (your key, not stored) checks it is a real reason.
- **Limits:** GitHub counts public repositories only; LeetCode has no official API, so it may stop working; a changed phone clock or Accessibility turned off can bypass it.
- **Semi is a different build, not a hidden one:** it contains none of this code.

### The screen is never captured

Reel Analyser never takes screenshots and never records the screen. The optional counter and blocker use Android's Accessibility service, which can read the layout of a screen, and they do that only in Instagram, YouTube and (for the address bar only) a browser, only after you allow it in the app, and they store only an anonymous fingerprint, counts and times. Read the details in the Privacy Policy.

### What leaves your phone

- **Reels you share:** sent to the AI provider you chose, with your own key.
- **Instagram's public pages:** loaded logged out, from your phone, only for reels you shared.
- **Feedback:** Settings → *Send feedback* opens a GitHub issue that you review before posting.

Nothing else leaves the phone: no analytics, no tracking, no Reel Analyser server.

## Technical workflow

### Components

```
┌──────────────────────── Android phone ────────────────────────────────────────┐
│                                                                               │
│  Kotlin plugin (mobile/packages/reelbot_native)    Flutter app (mobile/lib)   │
│  ─────────────────────────────────────────────     ────────────────────────   │
│  ShareReceiverActivity   share in (links, photos)  Runner     queue → notes   │
│  InstagramFetcher        logged-out cascade        Gemini / ChatModel  AI     │
│  ReelCounterService      Accessibility counter,    LibraryDb  notes, chats    │
│  BlockActivity, BlockPolicy  reel blocker (full)                              │
│                                                    KeyStore   keys, flags     │
│  DigestWorker            9 pm digest               UI: Ask, Insights, Library │
│  CounterDb (counter.db)  queue + counts                                       │
│            ▲                                                ▲                 │
│            └──────── method channel "reelbot/counter" ──────┘                 │
└───────────────────────────────────────────────────────────────────────────────┘
```

The Kotlin side is a Flutter **plugin** rather than code in `MainActivity`. That way the background engine started by `workmanager` can call it too.

### Where things are stored (all on the phone)

| Store | Owner | Holds |
|---|---|---|
| `counter.db` (SQLite) | Kotlin | `pending_items`: the queue (link or `photo:<path>`, status, note title). `seen_items`: one anonymous fingerprint per reel watched per day, with time and dwell, never the content. `screen_time`, `unknown_items`, `debug_state`. Blocker (full build): `block_state` (rules, suspended day), `block_use` (reel minutes per day and app), `block_events` (history, no photos). |
| `reel_brain.db` (SQLite) | Dart | `reels`: notes (title, summary, key points, tags, author, source, seen/archived). `chats`: saved conversations. `meta`: a lock so the app and the background job never analyse at the same time. |
| Encrypted secure storage | Dart | API keys (several Gemini, OpenAI, Claude, Groq, Apify) and small flags (theme, intro seen). |
| `files/photos/*.jpg` | Kotlin | Photos you shared, kept so their notes can show them. |
| `cache/ig/*.mp4` | Kotlin | A downloaded reel, deleted right after analysis. |
| `Downloads/ReelBot/` | you | Export: `library.json` (notes and saved chats) plus one Markdown file per note. |

### Background jobs

| Job | Scheduler | When | Does |
|---|---|---|---|
| `analyse` | `workmanager` (Dart) | every 15 min, needs network, plus on app open | runs the queue, then posts "Note ready" |
| `reelbot_digest` | WorkManager (Kotlin) | hourly; posts once after 21:00 | digest, or a nudge, on days the app wasn't opened |

### How each item is analysed

1. **YouTube Short:** the link is rewritten to `youtube.com/watch?v=ID` and sent to Gemini as `fileData`, so Gemini watches it itself and nothing is downloaded. If Gemini can't (a private video, or the daily cap), the note is made from YouTube oEmbed's title and thumbnail.
2. **Instagram reel:** `InstagramFetcher` tries these steps in order, logged out, with 5 s between requests, and stops at the first one that finds the video:
   1. the embed HTML;
   2. the embed **player**: a hidden WebView presses play and takes the video it loads;
   3. the post page JSON;
   4. the logged-out GraphQL query;
   5. the web GraphQL query;
   6. oEmbed (caption and thumbnail only);
   7. Apify, if you added a token.

   The video (≤ 100 MB) is downloaded, sent to Gemini (inline up to 20 MB, otherwise through the Files API), and then deleted. A login page only skips that step; an HTTP 429 (rate limit) pauses Instagram calls for 30 min, and a reel where every step hit a login page is retried after 10 min (3 tries).
3. **Instagram photo post or carousel:** the same steps collect every still image. Up to 10 are downloaded and sent in one request.
4. **Shared photo:** the JPEG from app storage is sent as one image.
5. **No media at all:** the note is made from the caption, the thumbnail and any on-screen text, and is marked as such.

**Provider order for notes:**
- Gemini first. It uses your keys in turn, one reel per key, and a 429 or a rejected key moves that reel to the next key.
- If every Gemini key fails or there are none, OpenAI and then Claude are tried, with 6 JPEG frames taken from the video (`MediaMetadataRetriever`) or the pictures.

**Token savers:** the cheapest model first; on Gemini, minimal thinking, low media resolution and video sampled at 0.5 fps (a retry drops these settings if a model rejects them); and a JSON note with fixed fields (title, overview bullets, summary, key points, mentions, tags).

### Counting reels you watch

```
Accessibility events ─▶ DetectionRules (is this Reels/Shorts? read author, caption, likes)
                     ─▶ ReelTracker (fingerprint, 1.5 s dwell, per-day dedupe, screen time)
                     ─▶ counter.db ─▶ Insights tab, Ask strip, digest
```

The service does nothing until you allow it in the app (`detect_consent`). The fingerprint is a SHA-1 of the app, author, the first 40 caption characters, the audio and the title. Only that hash is stored. If 5 or more reels in a day (and at least 30% of them) can't be read, one "counting may be broken" alert is posted.

### Blocking reels (full build)

```
Accessibility events ─▶ is a reel/short on screen? (ids only; browser: address bar)
                     ─▶ BlockMeter (reel time per app and day) ─▶ BlockPolicy.verdict(limit, slots)
                     ─▶ Block ─▶ BlockActivity over the reel (quote, Close after 3 s)
```

`BlockPolicy` is pure Kotlin with unit tests: shared or separate limits, slots (also across midnight), both must pass, a change to rules already on waits for the next midnight. State lives in `counter.db` so the service needs no Flutter engine. The detection of Instagram Reels uses ids that exist only in the Reels viewer; the Reels button of the bottom bar is deliberately not one of them, as it is on screen in the feed too.

### Chat

Each question searches every note you haven't deleted, archive included: the 12 best keyword matches go in full (overview, points, mentions, link) and the next 40 as title plus overview. It also sends the last 10 turns. No embeddings, and no server.

### Outside services

| Service | Used for | Sent |
|---|---|---|
| `www.instagram.com` (embed, post page, GraphQL, oEmbed), `*.cdninstagram.com` / `*.fbcdn.net` | fetching reels and posts you shared | public page requests, logged out |
| `youtube.com/oembed` | title and thumbnail when Gemini can't watch a Short | the Short's link |
| `generativelanguage.googleapis.com` (Gemini) | notes and chat | the video, link or images, plus your key |
| `api.openai.com` | fallback notes and chat | frames or images, plus your key |
| `api.anthropic.com` (Claude) | fallback notes and chat | frames or images, plus your key |
| `api.groq.com` | chat only | your question and the matching notes |
| `api.apify.com` | optional last resort for Instagram | the post's link, plus your token |
| `github.com` (browser) | feedback | only the text you type, after you review it |
| `api.github.com` | update check, at most once a day | nothing but the request itself (no token) |

## Install

1. Pick a version. **Full** (`reel-analyser-vX.Y.Z-full.apk`) has every feature, including Insights and reel counting. **Semi** (`reel-analyser-vX.Y.Z-semi.apk`) asks for no permission beyond the internet: no Insights, no notifications, no in-app updating. It has its own app id and icon, so it installs next to the full build and keeps its own notes and keys. Download it from [Releases](https://github.com/nevil-sanish/reel-analyser/releases) and open it. If Play Protect warns, choose *Install anyway*.
2. Slide to unlock through the intro, then open **Ask → ⚙ Settings** and paste a free Gemini key from [aistudio.google.com](https://aistudio.google.com/apikey). Optionally add OpenAI, Claude or Groq keys.
3. Share a reel to Reel Analyser. Its note appears in the Library within about 15 minutes, or immediately when you open the app.
4. For Insights, go to **Settings → Set up Insights** and allow **Usage access** (time in Instagram and YouTube) and notifications. To also **count** reels and Shorts, or to use the **Reel blocker** (both optional): on Android 13+, *Allow restricted settings* first, then Accessibility, then switch on **Allow reading the reel screens** in the app, then unrestricted battery, and Autostart on Xiaomi, Realme, Oppo and Vivo phones. Reel blocker is in **Settings → Reel blocker**.

Uninstalling deletes your notes, so use **Settings → Export** now and then. A banner tells you when a newer APK is out. The step-by-step guide for friends is [INSTALL.md](docs/INSTALL.md).

## Build

Flutter 3.47 (Dart 3.13), JDK 21, Android SDK 36.

```bash
cd mobile && flutter analyze && flutter test
```

```bash
cd mobile/android && ./gradlew :reelbot_native:testDebugUnitTest
```

```bash
cd mobile && flutter build apk --release --flavor full -t lib/main_full.dart
```

```bash
cd mobile && flutter build apk --release --flavor semi -t lib/main_semi.dart
```

`full` has every feature. `semi` asks Android for nothing beyond the internet: no Accessibility, Usage access, notifications or battery exemption, no Insights, no Reel blocker, no in-app updating.

The release build needs `mobile/android/key.properties` (gitignored) pointing at a keystore kept outside the repo.

**Layout:**
- **Flutter app** (`mobile/lib`): `pipeline/` holds the analysis runner and providers, `data/` the library database and keys, `ui/` the screens.
- **Kotlin** (`mobile/packages/reelbot_native`): the share receiver, the Instagram fetcher, the counter's Accessibility service, and the digest.

## About the developer

Made by **Nevil Mathew Sanish** ([github.com/nevil-sanish](https://github.com/nevil-sanish)), an independent developer. The same text is in the app: Settings, About the developer.

Thank you to **Sanjay S**, **Ashin Antony** and **Harry SP** for helping, suggesting and contributing.

## License and legal

The source code is under the **MIT License**, see [LICENSE](LICENSE). Names and third-party notices are in [NOTICE.md](NOTICE.md).

The app's legal texts are bundled in the app (Settings → About and legal) and are the public versions here:
- [Privacy Policy](mobile/assets/legal/privacy.md)
- [Terms of Use](mobile/assets/legal/terms.md)
- [Disclaimer](mobile/assets/legal/disclaimer.md)

Reel Analyser is an independent project and is not affiliated with Instagram, Meta, YouTube, Google, OpenAI, Anthropic, Groq or Apify.

## Docs

| Doc | What's in it |
|---|---|
| [STATUS.md](docs/STATUS.md) | **Start here:** what's done, how it was checked, and every piece of work still to do |
| [INSTALL.md](docs/INSTALL.md) | One-page install guide for friends |
| [PLAN.md](docs/PLAN.md) | What we're building, decisions, risks, build order |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | File-by-file guide, with what changed in each version |
| [ENDPOINTS.md](docs/ENDPOINTS.md) | Every network call and internal interface |
| [TESTS.md](docs/TESTS.md) | Test catalogue with IDs |
| [RESEARCH.md](docs/RESEARCH.md) | Survey of ~30 open-source Instagram/YouTube fetchers |
| [RELEASES.md](docs/RELEASES.md) | Commits, keeping docs in step, GitHub Releases |
