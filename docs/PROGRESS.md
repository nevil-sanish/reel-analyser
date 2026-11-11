# Progress (written 2026-11-09, about 21:20 IST)

Hand-off for a new chat. The list of what is still to do is in [TODO.md](TODO.md). Read this first, then that.

## Latest (2026-11-11): v1.2.1.0 released

- v1.2.1.0: LinkedIn multi-part analysis, the Support and Refund Policy and updated legal texts, and F-Droid groundwork. The F-Droid recipes are in `fdroid/`, and [FDROID.md](FDROID.md) explains them and the submission steps, which need the user's GitLab account.

- v1.2.0.0 is the Latest release on GitHub (both APKs and SHA256SUMS). It closes issues #1, #3, #4, #5, #7, #8, #9, #10 and #11; see RELEASES.md for what is in it and what was checked.
- Still open: **#2** (the user tests the GitHub, Codeforces and LeetCode goals with their own accounts) and **#6** (F-Droid, next).
- The sections below are older hand-off notes from 2026-11-09 and describe past states.

## Where things stood (2026-11-09)

- **Released and published:** v1.1.0.0 (Latest on GitHub, both APKs, `nevil-sanish/reel-analyser`). `main` is at `ff4f860`. Everything up to and including the new gold-and-white design and logo is in it.
- **Not committed, not released:** the 1.1.1.0 work (Daily goals, the Full/Semi split, the new tabs, updated legal texts). It is all in the working tree. A full copy as one patch is in `mobile/build/backup-1.1.1.0-wip/all-changes.patch` (git-ignored folder; `git apply` it onto `ff4f860` to restore).
- **The code does not compile right now.** The Full/Semi split is half done (see "Split status"). `flutter analyze` shows errors, listed in TODO.md step A.
- **On the user's phone:** a 1.1.1.0 build from *before* the split is installed (Full `app.reelbrain` and Semi `app.reelbrain.semi`). In it Daily goals work and are reached from Settings. The new tabs and the split are not on the phone yet.

## What shipped earlier this session (all released)

| Version | What |
|---|---|
| 1.0.8.0 | Chat about a single note (own saved thread per note, "Short & simple" preload), both builds |
| 1.0.9.0 | **Reel blocker** (Full only): limits and schedules for Instagram Reels, YouTube Shorts and browser reel pages; block screen with a 3 s Close; face-photo cancel for a day; typed 50-word paragraph to remove for good; history; opt-in "Allow reading the reel screens"; Instagram detection fix (the Reels tab button no longer counts as "on Reels") |
| 1.1.0.0 | Hellenic gold-and-white design for both builds, new logo (gold Greek-key ring + play mark, silver for Semi), bundled fonts (Cormorant Garamond serif, Lato), motion, vibration setting, About the developer, legal texts 1.1 |

## 1.1.1.0: what is done (uncommitted)

### Daily goals (Full only)
- **Rules, verified against the live services** (all three reachable without any key or login):
  - GitHub: `GET api.github.com/search/commits?q=author:USER author-date:START..END` with the phone's local day and UTC offset. Matched local git counts exactly. Public repositories only. (The events API was delayed and no longer carries commit counts, so it is not used.)
  - Codeforces: `codeforces.com/api/user.status?handle=H&from=1&count=100`; counts different problems with verdict `OK` that day.
  - LeetCode: `POST leetcode.com/graphql` with `matchedUser` and `recentAcSubmissionList(limit 20)`; counts different `titleSlug` that day. Unofficial API: may stop working. Disclosed everywhere.
- **Fail open:** a site that cannot be read is never a miss. A day is retried until it is 3 days old, then dropped as unknown. "At least n" counts that are not provably short are unknown, not misses.
- **Judging:** a finished day is judged 20 minutes after midnight, once, using the goals that were in force that day (goals are stored with the date they start to count). Up to 7 days back.
- **Penalty:** **changed 2026-11-11 (issue #5): each missed day blocks only the next day** (misses in a row block day after day); a met day adds no block and never lifts one already running. (Was 1, 2, 4 days until 1.1.1.2.) The handle-change reason may be sent to the user's own AI key (confirmed 2026-11-09).
- **What is blocked:** the whole Instagram app (and YouTube if chosen). Not cancellable for the day. Goals can be edited only 00:00 to 00:10 after the first set-up.
- Files: `mobile/lib/full/goals.dart` (fetchers, rules, engine), `goal_store.dart` (tables), `goals_screen.dart`, `mobile/test/goals_test.dart` (19 tests, all passed before the split).
- **Kotlin, done and tested** (before the planned flavour split): `Punish` model in `BlockPolicy.kt`; `punish` kv in `CounterDb.kt`; `ReelCounterService.kt` blocks the whole app (`blockNow`, reason `commit`, no screen reading while blocked); `BlockActivity.kt` shows "Instagram is blocked ... opens again after <date>"; plugin method `punishSet`; 2 new Kotlin tests.
- Storage: only on the phone. Tables `goal_cfg`, `goal_days` (and an unused-yet `goal_changes`) in `reel_brain.db`. Day results are pruned after 90 days. Erase all my data clears them.

### Legal and docs (done, uncommitted)
- Privacy Policy 1.2, Terms 1.2 (new section 7 "Daily goals", later sections renumbered), Disclaimer 1.1, NOTICE.md trademarks. First-start agreement flag is now `legal_v3` (everyone sees it again). `test/legal_test.dart` updated.
- **Still to update** for the new things (see TODO.md F): the handle-change explanation is analysed by the user's AI provider (a new thing that leaves the phone), the About tab wording, build commands, ENDPOINTS/TESTS/RELEASES/README.

### Version
`AppServices.version = '1.1.1.0'`, `pubspec.yaml` `1.1.1+40`.

## Split status (Dart): half done

The user's rule: Semi must not *contain* Full-only features at all (not just hide them). A measurement of the Semi APK confirmed the old approach leaked: the Dart snapshot still had `api.github.com` and goals strings, and the Android dex still had `blockSave`, `punishSet`, `detectionConsent`, `setCapture`, `appUsage` handlers.

Chosen approach (reviewed): separate Dart entry points and matching Android flavours for the Kotlin plugin.

**Done in Dart:**
- Entry points `lib/main_full.dart` and `lib/main_semi.dart`; the shared shell is `lib/app.dart` (`runReelBot(features, backgroundDispatcher)`). `lib/main.dart` and `lib/flavor.dart` are gone. Build with `-t lib/main_full.dart` / `-t lib/main_semi.dart`.
- `lib/features.dart`: `AppFeatures` (extra tabs, Ask strip, Settings sections, onOpen, inBackground, notifyNotes, erase, update strategy). `lib/semi_features.dart` (empty). `lib/full/full_features.dart` (Insights tab, Blocker tab, today strip, Insights setup, goals engine, midnight/open hooks, in-app updater).
- Moved to `lib/full/`: insights, setup, debug, blocker screen, goals screen, detect_consent, `blocker.dart` (blocker bridge + models + `ParagraphGuard`), `goals.dart`, `updater.dart`; new: `full_bridge.dart` (the counter/usage/notify/updater channel methods and their models), `goal_store.dart`, `today_strip.dart`, `blocker_tab.dart`.
- Shared `CounterBridge` now only has what both builds use (queue, Instagram fetch, openUrl, sweepPhotos, watchdog, eraseAll, saveDownload, videoFrames).
- `AppServices.create(features)` and a `features` field; `LibraryDb` keeps `version: 7` with a no-op `_v7` (the phone already has v7) and exposes `raw` for the Full-only `GoalStore`.
- New shared UI: `ui/about_screen.dart` (About tab: developer, feedback, updates, privacy, terms, disclaimer, licences), `ui/section_card.dart`. Settings now holds keys, appearance, Full-only Insights setup, backup, erase. The "Reel blocker" Settings section is gone (it is the Blocker tab).
- Tabs: Ask, [Insights], Library, [Blocker], About (brackets = Full only).

**Not done:** everything under "Kotlin" below, the Dart compile errors, the guard test, and all the tests' new imports. See TODO.md.

## Facts and decisions worth keeping

- Never `am force-stop` the app on the phone: Android then switches the Accessibility service off and the user has to turn it on again. Install with `adb install -r` only.
- The user is often using the phone. Locate a control (dump the UI) before tapping. Never type or tap inside Instagram except a deep link or a tab button. Do not screenshot the home screen (personal widgets).
- The first-start agreement dialog (`legal_v3`) must be accepted by the user, never by an automated tap.
- The Accessibility service class name `app.reelbrain.ReelCounterService` must not change (Android keys the user's toggle on it).
- `dart format` on existing files rewraps them; do not run it on existing files (new files are fine).
- No attribution lines in commit messages. Commit and publish only when asked (the user has asked for the 1.1.1.0 release once the work is finished and checked).
- Tools: Flutter, JDK and Android SDK are under `~/development` (not on PATH). Release signing key in `~/.reelbot` (symlinked as `mobile/android/key.properties`, git-ignored).
- Phone: Nothing A059, adb serial `00163354U000052`, Android 16.
- Test counts before the split: 109 Dart tests passed; Kotlin tests passed (`./gradlew :reelbot_native:testDebugUnitTest`).

## Update, 2026-11-09 night (after the hand-off)

Done and checked without the phone: TODO A, B, C, D, E and F. `flutter analyze` clean, 118 Dart tests, Kotlin `testFullDebugUnitTest` (81) and `testSemiDebugUnitTest` (33) pass, `tool/check_apks.sh` passes on freshly built release APKs (signer `CN=Reel Bot`, version code 40, no CAMERA permission). Both APKs, `SHA256SUMS` and `notes.md` are in `mobile/build/release-v1.1.1.0/`.

Decisions: penalty 1 day per miss (since 2026-11-11, was 1, 2, 4); handle-change reason goes to the user's own AI key (both confirmed).

**Left, needs the phone and the user:** TODO G steps 3 to 5 (install over the existing apps with `adb install -r`; the user taps "I agree" on `legal_v3`; check the five tabs, Semi's three, the Blocker tab, locked handles flow, a penalty block via a manual `punishSet`; then commit, push and `gh release create v1.1.1.0`). Not built in: rest days and a midnight "missed" notification (not requested). Known bypasses left in the Terms: phone clock, Accessibility off, Erase all my data.
