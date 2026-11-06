# Reel Bot

Android app that turns the Instagram Reels, YouTube Shorts, Instagram posts and photos you share to it into short AI notes you can search and chat with, and counts how many reels and shorts you watch. It uses your own AI keys. There is no account and no server: everything lives on your phone.

**Download:** [latest APK](https://github.com/nevil-sanish/reel-brain/releases) (Android 10+).

## How it works

### 1. Save: share anything to Reel Bot

```
Instagram / YouTube / Gallery ──Share──▶ Reel Bot ──▶ "Saved ✓" (you stay where you were)
                                            │
                                            ▼
                                  queue on the phone (counter.db)
```

- **Reels, Shorts and Instagram posts:** tap **Share → Reel Bot**. On Instagram, use *Share → Share to…*. The link is cleaned of tracking codes and queued.
- **Photos and screenshots:** share one or several from any app. Each picture is copied into the app, shrunk to 1280 px, and queued as its own note.
- That's the only way in: no floating button over the apps you watch.

### 2. Analyse: in the background, every 15 minutes and whenever you open the app

```
queued item ──▶ get the media ──▶ AI makes a note ──▶ Library  (+ "Note ready" notification)
```

| You shared | How Reel Bot gets it | What the AI sees |
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
- **Library:** every note, filterable by Reels, Shorts, Posts and Photos. A dot marks notes you haven't opened. Swipe left to delete (with Undo), right to archive, or long-press to select several, then mark them read, archive or delete them. Notes you've read move to the Archive after 3 days.

### 4. Time and counts: Usage access, plus optional Accessibility

Both are optional; notes and chat work without them.

**Time in Instagram and YouTube** comes from Android's own app-usage data (Usage access). Nothing is read from the screen, and it's time in the whole app, not only Reels or Shorts.

**Counting reels and Shorts is optional.** Turn on Accessibility as well, and Reel Bot reads the Reels and Shorts screens to count what you watch and the time on those screens:
- a reel counts after 1.5 seconds on screen;
- swipe-backs and rewatches the same day don't count twice;
- it keeps only an anonymous fingerprint of each reel, never what it was;
- it never taps, types or scrolls.

After 9 pm, on days you didn't open the app, you get one digest notification.

### What leaves your phone

- **Reels you share:** sent to the AI provider you chose, with your own key.
- **Instagram's public pages:** loaded logged out, from your phone, only for reels you shared.
- **Feedback:** Settings → *Send feedback* opens a GitHub issue that you review before posting.

Nothing else leaves the phone: no analytics, no tracking, no Reel Bot server.

## Technical workflow

### Components

```
┌──────────────────────── Android phone ────────────────────────────────────────┐
│                                                                               │
│  Kotlin plugin (mobile/packages/reelbot_native)    Flutter app (mobile/lib)   │
│  ─────────────────────────────────────────────     ────────────────────────   │
│  ShareReceiverActivity   share in (links, photos)  Runner     queue → notes   │
│  InstagramFetcher        logged-out cascade        Gemini / ChatModel  AI     │
│  ReelCounterService      Accessibility counter     LibraryDb  notes, chats    │
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
| `counter.db` (SQLite) | Kotlin | `pending_items`: the queue (link or `photo:<path>`, status, note title). `seen_items`: one anonymous fingerprint per reel watched per day, with time and dwell, never the content. `screen_time`, `unknown_items`, `debug_state`. |
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

The fingerprint is a SHA-1 of the app, author, the first 40 caption characters, the audio and the title. Only that hash is stored. If 5 or more reels in a day (and at least 30% of them) can't be read, one "counting may be broken" alert is posted.

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

1. Download `reel-bot-vX.Y.Z.apk` from [Releases](https://github.com/nevil-sanish/reel-brain/releases) and open it. If Play Protect warns, choose *Install anyway*.
2. Slide to unlock through the intro, then open **Ask → ⚙ Settings** and paste a free Gemini key from [aistudio.google.com](https://aistudio.google.com/apikey). Optionally add OpenAI, Claude or Groq keys.
3. Share a reel to Reel Bot. Its note appears in the Library within about 15 minutes, or immediately when you open the app.
4. For Insights, go to **Settings → Set up Insights** and allow **Usage access** (time in Instagram and YouTube) and notifications. To also **count** reels and Shorts (optional): on Android 13+, *Allow restricted settings* first, then Accessibility, unrestricted battery, and Autostart on Xiaomi, Realme, Oppo and Vivo phones.

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
cd mobile && flutter build apk --release
```

The release build needs `mobile/android/key.properties` (gitignored) pointing at a keystore kept outside the repo.

**Layout:**
- **Flutter app** (`mobile/lib`): `pipeline/` holds the analysis runner and providers, `data/` the library database and keys, `ui/` the screens.
- **Kotlin** (`mobile/packages/reelbot_native`): the share receiver, the Instagram fetcher, the counter's Accessibility service, and the digest.

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
