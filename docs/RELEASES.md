# Reel Analyser: commits, docs and releases

How work lands in this repo. Applies to people and to coding agents.

## 1. Commits

- **One branch: `main`.** No long-lived branches.
- **Author: `nevil-sanish <nevilsanish@gmail.com>`** (the repo's git config). No co-author or "generated with" trailers.
- **Commit often and small:** one commit per logical step (one endpoint, one screen, one test group, one doc section), pushed straight after. A day's work is several commits, not one.
- **Message:** short imperative sentence saying what changed and why, e.g. "Parse embed contextJSON for reel video URLs". No prefixes.
- **Never** commit keys, `.env`, `*.jks`, `key.properties`, or fixtures containing cookies or tokens.
- **Never** force-push or rewrite pushed history.

## 2. Docs and tests stay in step with code

In **the same commit** as the change:

| If you change… | Also update |
|---|---|
| Any network request (URL, header, body, parsed field, `doc_id`) | [ENDPOINTS.md](ENDPOINTS.md) card + its change log |
| Any behaviour with a test ID | [TESTS.md](TESTS.md) row (status: planned → written → passing) |
| A new endpoint or feature | Both: a new card, and new test rows linked to it |
| The fetch order or a phase's scope | [PLAN.md](PLAN.md) §3.2 / §6, and [IMPLEMENTATION.md](IMPLEMENTATION.md) |
| What open-source projects do (after re-checking) | [RESEARCH.md](RESEARCH.md) |

A commit that changes code but leaves a covering test row at **planned** is incomplete.

## 3. Versions

`v<major>.<minor>.<patch>`, pre-1.0 while Reel Analyser is personal:

| Version | Meaning |
|---|---|
| `v0.0.x` | Docs only (plans, endpoint map, test catalogue). No APK |
| `v0.1.x` | Phase 1: Share → summary |
| `v0.2.x` | Phase 2: counter |
| `v0.3.x` | Phase 3: bubble (+ auto-Save if it passes the 90% bar) |
| `v0.4.x` | Phase 4: digest |
| `v1.0.0` | First version given to friends, with `docs/INSTALL.md` (planned, PLAN §6) |

`pubspec.yaml` `version:` = `0.1.0+<build>`; the build number only goes up. The app's update check (`GH-RELEASE-LATEST`) compares against the release tag.

## 4. GitHub Releases

Every version is a GitHub Release on `nevil-sanish/reel-analyser`:
- **Tag** `vX.Y.Z` on `main`, created by the release itself.
- **Pre-release** flag on while `< v1.0.0`.
- **Assets** (from `v0.1.0`): `reel-analyser-vX.Y.Z.apk` (release build, signed with the private key kept outside the repo) and `SHA256SUMS`.
- **Notes**, in this order:
  1. What changed (from the commits since the last tag).
  2. Live checks ([TESTS.md](TESTS.md) §6): which Instagram step won for each test URL, and the T-LIVE-10 video rate.
  3. Manual checks run (§7) and their results.
  4. Known issues.

Commands:

```bash
git tag --list 'v*' --sort=-v:refname | head -1
```

```bash
gh release create vX.Y.Z --target main --prerelease --title "vX.Y.Z: <summary>" --notes-file notes.md reel-analyser-vX.Y.Z.apk SHA256SUMS
```

Release checklist:
1. `main` is pushed and clean.
2. Unit, fixture and integration tests pass; `flutter analyze` is clean.
3. Live checks run on a phone within the last 24 h.
4. ENDPOINTS.md and TESTS.md change logs mention this version.
5. Create the release; install the APK from the release page on a phone (T-MAN-01).

## 5. Change log

| Date | Version | Change |
|---|---|---|
| 2026-11-05 | v0.0.1 | Plan, open-source survey, endpoint map, test catalogue. |
| 2026-11-05 | v0.1.0 | Phase 1: Share → summary. First APK (pre-release). Live and manual checks not yet run. |
| 2026-11-05 | v0.1.1 | The library shows why queued items are waiting (Gemini HTTP status, network, Instagram pause, held lock); uncaught errors now mark an item failed instead of leaving it queued. |
| 2026-11-06 | v0.2.0 | Phase 2: counter. Accessibility service, Today/History, setup checklist, debug screen with capture, unknown alert. Detection ids are the docs' starting guesses until captured from a phone. |
| 2026-11-06 | v0.3.0 | Phase 3: bubble with Today count and Save; experimental auto-Save (off by default) with its success rate on the debug screen. Not yet measured against the 90% bar. |
| 2026-11-06 | v0.4.0 | Phase 4: evening digest notification (after 21:00, only on days the app was not opened). |
| 2026-11-06 | v0.5.0 | New look and intro; chat over saved notes with Gemini/OpenAI/Claude/Groq; rotating Gemini keys; OpenAI/Claude fallback from frames; fewer video tokens; YouTube as watch URLs; Instagram rendered-page fallback; watched reels kept as fingerprints only; feedback via GitHub issue. |
| 2026-11-06 | v0.6.0 | Chat is the home tab with a provider + model picker; cheaper models first and smaller chat context; Reels-gradient theme and slide-to-unlock intro; seen dot and 3-day archive; note-ready notification and 9 pm nudge. |
| 2026-11-06 | v0.6.1 | Shorter notes (1 sentence, up to 3 points and tags) for fewer tokens and a cleaner note screen; haptic feedback across the app. |
| 2026-11-06 | v0.6.2 | Instagram embed-player step against "text only" notes, with one-time retry and a Try again button; swipe to delete or archive; saved time on notes. |
| 2026-11-06 | v0.7.0 | Liquid-glass look: drifting gradient background, frosted cards and floating tab bar, iOS-style transitions; chat opens on one big ask bar that glides into the conversation. |
| 2026-11-06 | v0.8.0 | Share photos and screenshots to Reel Bot; Instagram photo posts and carousels analysed from all their images. |
| 2026-11-06 | v0.8.1 | Green theme (light default, dark toggle); liquid transitions; Ask with saved chats and a today strip; Insights by day, hour and weekday; Library filters; compact notes with a full-analysis toggle. |
| 2026-11-06 | v0.8.2 | Fix tabs overlapping; fewer buttons and hints; README explains the workflow; repo renamed to reel-brain. |
| 2026-11-06 | v0.9.0 | Floating bubble and auto-Save removed: saving is Share → Reel Bot only. Multi-select in Library and Archive (mark read, archive / restore, delete). |
| 2026-11-06 | v0.9.1 | Instagram: a login page skips one step instead of pausing everything for 30 min; only real rate limits pause. |
| 2026-11-06 | v0.9.2 | Richer notes (overview bullets + full detail + mentions, Re-analyse); chat uses full notes incl. archive; readable Insights; new Ask home. |
| 2026-11-06 | v0.9.3 | Search covers overview and mentions; Re-analyse old notes; orphan photo cleanup; time-of-day ranked by minutes. |
| 2026-11-06 | v0.9.4 | Export/Import include saved chats; share several photos at once; update banner; INSTALL.md; PLAN.md up to date. *Built but never published; its changes ship in v0.9.5.* |
| 2026-11-06 | v0.9.5 | Everything from v0.9.4, plus: re-sharing a saved reel brings it back unread instead of re-analysing; Undo on every note action; time in Instagram and YouTube from Usage access (optional), reel counting optional, Reduce effects, new app icon; fixes found on a phone (background job closed the app's database, setup said Accessibility was off, private posts shown as a rate limit, app time ~20% low). |
| 2026-11-07 | v0.9.6 | Saved API keys no longer vanish (Save blocked until keys load, plugin reset-on-error off, background job no longer writes to secure storage, auto-backup off); reels shared while a run is busy are picked up in the same run; Instagram pacing 1.5 s, pause 10 min after a rate limit; one Gemini 429 retry per run; transcript, on-screen text and caption in the full analysis; Mark unread (note screen and multi-select); new app icon. *Not yet checked on a phone: multi-share, transcript, keys surviving a force-stop.* |
| 2026-11-07 | v0.9.7 | Parallel analysis: one reel per Gemini key at the same time (up to 4), each worker starting on its own key; native job pool 2 → 4 threads; the Library lists every reel being analysed with its own progress bar and a Stop button (a stopped reel is not analysed); app and repo renamed to Reel Analyser (package id unchanged, so it installs over v0.9.6). *Not yet checked on a phone.* |
| 2026-11-07 | v0.9.7.1 | Keys save as you type (no Save button; a failed key read blocks autosave instead of overwriting); reels named in the progress list (from the share time, then caption/author, then the AI's title); errors explained with their real cause and kept in the list until dismissed; "Re-analyse old notes" removed; chat gets every note's full content (transcript, on-screen text, caption) and answers only from them; startup and import no longer crash on a phone error. Four-part version: pubspec says 0.9.7+22, the build passes `--build-name=0.9.7.1`. |
| 2026-11-07 | v0.9.8 | Backup can include your API keys, encrypted (AES-256-GCM, key from a passphrase you choose, PBKDF2-SHA256 120k); Import asks for the passphrase and restores them. Open a note's link inside the app (in-app web view, with back, reload and open-in-app). *Not yet checked on a phone.* |
| 2026-11-07 | v0.9.9 | Play Store readiness: Privacy Policy and Terms of Use (bundled, shown for agreement on first start, Settings → About and legal), open-source licenses, Erase all my data, retention enforced (Insights 90 days, finished queue entries 30 days), prominent disclosure before Usage access / Accessibility, `direct` and `play` flavors (the Play build has no Accessibility service, battery exemption, Counter debug or update banner), PLAY_STORE.md. Security: only Instagram/YouTube https links open from notes, PBKDF2 600k rounds with bounded accepted range, hostile-import tests. *Not yet checked on a phone.* |
| 2026-11-07 | v1.0.0.0 | First full release. MIT license. Two APKs per release: `full` (every feature) and `private` (no Accessibility, Usage access, notifications or battery exemption; no Insights, update check or notifications; only INTERNET plus WorkManager's automatic permissions). Flavors renamed from direct/play. |
| 2026-11-07 | v1.0.0.1 | Analysis works with the app closed: sharing starts it at once (an expedited background task), a run killed with the app resumes within about 2 minutes (watchdog + 90 s queue lock), the background task waits for the queue lock instead of retrying later. Reels shared while others are being analysed start at once on a free key. |
| 2026-11-07 | v1.0.0.2 | API keys save the instant they change (no 0.7 s wait, writes queued in order, leaving the screen straight after typing loses nothing, and one failed read no longer switches saving off). The intro and the Terms agreement are remembered in a plain file instead of the Keystore, so they no longer come back at every start; older installs are migrated on first read. |
| 2026-11-07 | v1.0.1.0 | Keys and flags no longer use the Android Keystore plugin, which on some phones throws "Migration failed after algorithm change" on every read and write (found on a USB-connected phone): they live in a private app file, older Keystore values are copied once. A tick button next to each key saves it at once. Imported notes must have an https link or a photo inside the app's photos folder; the in-app page loads https only; Import refuses files over 50 MB. Checked on a phone: a key typed, app force-stopped and reopened, key still there. |
| 2026-11-07 | v1.0.2.0 | API keys are encrypted (AES-256-GCM, a Keystore key the app makes itself, `SecretBox.kt`) before they are written to the private file; if the phone's Keystore refuses, the key is still saved so typing one never fails. In-app page limited to Instagram, YouTube, Facebook-login and Google-consent hosts over https. One share is capped at 10 photos and 10,000 characters of text. *Encryption not yet checked on a phone (the phone was unplugged); the key-saving fix of v1.0.1.0 was.* |
| 2026-11-07 | v1.0.3.0 | Library shows a moving progress card (with the reel names) while the background task analyses, instead of only "waits for it". The update check now runs in the private build too: the two builds differ only by Insights and the permissions Insights needs. |
| 2026-11-07 | v1.0.4.0 | Each reel in the progress card shows Fetch, Analyse and Save with a percent, also when the background task is the one working; Stop works there and ends a reel at once, even mid-fetch. One export is one dated file (`library-<date>-<time>.json`), not a file per note. The settings file is no longer wiped when the app and the background task start together. Instagram waits shortened: 2 min after a 429 (was 10), 1 min for a login wall (was 3), 10 min for gone posts (was 1 h), 1 s between requests (was 1.5). Chat shows **bold** as bold. *Key encryption of v1.0.2.0 still not tested on its own on a phone.* |
