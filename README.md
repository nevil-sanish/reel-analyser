# Reel Bot

Android app that turns the Instagram Reels and YouTube Shorts you share to it into searchable AI notes, using your own Gemini key. Everything stays on the phone; there's no server.

**v0.1.x = Phase 1** (Share → summary). The reel/short counter, the floating bubble and the daily digest come later ([PLAN.md](docs/PLAN.md) §6).

## Install

1. Download `reel-bot-vX.Y.Z.apk` from [Releases](https://github.com/nevil-sanish/reel-notes-bot/releases) and open it. Allow installing from your browser or file manager if Android asks. If Play Protect warns, choose *Install anyway*.
2. Open Reel Bot → key icon → paste a free Gemini API key from [aistudio.google.com](https://aistudio.google.com/apikey) → *Save keys*.
3. In Instagram or YouTube, tap **Share** on a reel or short → **Reel Bot** (on Instagram: Share → *Share to…* first). You'll see "Saved ✓" and stay where you were.
4. Notes appear in the Library within about 15 minutes, or immediately when you open the app.

Uninstalling deletes the library: use Settings → *Export* now and then.

## Build

Flutter 3.47 (Dart 3.13), JDK 21, Android SDK 36.

```bash
cd mobile && flutter test && flutter analyze
```

```bash
cd mobile/android && ./gradlew :reelbot_native:testDebugUnitTest
```

```bash
cd mobile && flutter build apk --release
```

The release build needs `mobile/android/key.properties` (gitignored) pointing at a keystore kept outside the repo.

## Docs

| Doc | What's in it |
|---|---|
| [PLAN.md](docs/PLAN.md) | What we're building, decisions, risks, build order |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | File-by-file guide |
| [ENDPOINTS.md](docs/ENDPOINTS.md) | Every network call and internal interface |
| [TESTS.md](docs/TESTS.md) | Test catalogue with IDs |
| [RESEARCH.md](docs/RESEARCH.md) | Survey of ~30 open-source Instagram/YouTube fetchers |
| [RELEASES.md](docs/RELEASES.md) | Commits, keeping docs in step, GitHub Releases |
