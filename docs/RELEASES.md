# Reel Bot: commits, docs and releases

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

`v<major>.<minor>.<patch>`, pre-1.0 while Reel Bot is personal:

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

Every version is a GitHub Release on `nevil-sanish/reel-notes-bot`:
- **Tag** `vX.Y.Z` on `main`, created by the release itself.
- **Pre-release** flag on while `< v1.0.0`.
- **Assets** (from `v0.1.0`): `reel-bot-vX.Y.Z.apk` (release build, signed with the private key kept outside the repo) and `SHA256SUMS`.
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
gh release create vX.Y.Z --target main --prerelease --title "vX.Y.Z: <summary>" --notes-file notes.md reel-bot-vX.Y.Z.apk SHA256SUMS
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
