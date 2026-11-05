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
- **Photos and screenshots:** share them from any app. The picture is copied into the app, shrunk to 1280 px, and queued.
- **Bubble Save (optional):** while you watch, the floating bubble's **Save** queues what's on screen. Share the reel within 2 minutes so the note can use the video.

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

Notes are kept short to save tokens: a title, one sentence, up to 3 points and 3 tags.

### 3. Use: three tabs

- **Ask:** today's reels, shorts and minutes at the top, then a chat that answers only from your saved notes. Pick the provider and model from the chip above the ask bar. Every chat is saved; the clock icon reopens old ones.
- **Insights:** a Week or Month view of your watching: minutes per day, the hours you watch most, and your heaviest weekday.
- **Library:** every note, filterable by Reels, Shorts, Posts and Photos. A dot marks notes you haven't opened. Swipe left to delete (with Undo), right to archive. Notes you've read move to the Archive after 3 days.

### 4. Count: optional, through Android Accessibility

Reel Bot reads the Reels and Shorts screens to count what you watch and for how long:
- a reel counts after 1.5 seconds on screen;
- swipe-backs and rewatches the same day don't count twice;
- it keeps only an anonymous fingerprint of each reel, never what it was;
- it never taps or scrolls (the experimental Auto-Save is the only exception, and it's off by default).

After 9 pm, on days you didn't open the app, you get one digest notification.

### What leaves your phone

- **Reels you share:** sent to the AI provider you chose, with your own key.
- **Instagram's public pages:** loaded logged out, from your phone, only for reels you shared.
- **Feedback:** Settings → *Send feedback* opens a GitHub issue that you review before posting.

Nothing else leaves the phone: no analytics, no tracking, no Reel Bot server.

## Install

1. Download `reel-bot-vX.Y.Z.apk` from [Releases](https://github.com/nevil-sanish/reel-brain/releases) and open it. If Play Protect warns, choose *Install anyway*.
2. Slide to unlock through the intro, then open **Ask → ⚙ Settings** and paste a free Gemini key from [aistudio.google.com](https://aistudio.google.com/apikey). Optionally add OpenAI, Claude or Groq keys.
3. Share a reel to Reel Bot. Its note appears in the Library within about 15 minutes, or immediately when you open the app.
4. To count what you watch, go to **Settings → Set up counting** and follow the checklist: on Android 13+, *Allow restricted settings* first, then Accessibility, notifications, unrestricted battery, and Autostart on Xiaomi, Realme, Oppo and Vivo phones.

Uninstalling deletes your notes, so use **Settings → Export** now and then.

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
- **Kotlin** (`mobile/packages/reelbot_native`): the share receiver, the Instagram fetcher, the counter's Accessibility service, the bubble, and the digest.

## Docs

| Doc | What's in it |
|---|---|
| [PLAN.md](docs/PLAN.md) | What we're building, decisions, risks, build order |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | File-by-file guide, with what changed in each version |
| [ENDPOINTS.md](docs/ENDPOINTS.md) | Every network call and internal interface |
| [TESTS.md](docs/TESTS.md) | Test catalogue with IDs |
| [RESEARCH.md](docs/RESEARCH.md) | Survey of ~30 open-source Instagram/YouTube fetchers |
| [RELEASES.md](docs/RELEASES.md) | Commits, keeping docs in step, GitHub Releases |
