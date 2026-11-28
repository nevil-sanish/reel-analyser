# Progress (written 2026-11-09, about 21:20 IST)

## Latest (2026-11-28, ~13:25 IST): #53 chat less strict, phone-checked; NOT released

All three chats (one note, a folder, Ask) used to say "answer ONLY from the notes, never general knowledge, else say so and stop". Now they share `chatRules` in `app_services.dart`: notes first, related questions answered with general knowledge and labelled "not from the note", only clearly unrelated questions get one line "not related to this chat". Intro texts, the folder chat label and README updated. Phone (Gemini 3.5 Flash-Lite): note chat answered a related and a slightly different question with labels and refused a pizza question; Ask did the same (God Mode question, Paris weather refused). Folder chat uses the same rules but was not tried on the phone. The test conversations are still saved in that note's chat and in Ask.

## Latest (2026-11-28, ~13:10 IST): only #52 (Testing) and #6 (F-Droid) are open

At the user's request #2, #39, #40, #41 and #50 were closed and their phone checks moved into **#52 Testing** (Snapchat Spotlight, TikTok, goals with own accounts, scroll guard, smoothness). LinkedIn (#12, #44) closed after a phone test: four public posts saved (one alone, three shared together). The old test post `lnkd.in/p/dEG72umG` is login-only (page redirects to sign-up, embed 404) and Apify (key accepted) returns nothing for it; that is expected. Apify has never been seen returning a post, because public posts load from the page or embed first. Still on the phone: the youtube.com 0-min site limit (until midnight) and a failed-share card for the login-only post.

## Latest (2026-11-28, ~13:00 IST): #51 site blocker (Accessibility method) fixed and phone-checked; NOT released

**#51.** (1) Typing a limited site in Chrome's address bar sent the person home before Enter: `ReelCounterService.readAddress` now ignores the bar while it has focus. (2) Reopening a blocked site could get through: the site re-block gap is 1.2 s (`SITE_GAP_MS`, was the 4 s Home gap), and `FrontAddress` (`SiteFilter.kt`) keeps the last opened address while Chrome hides its bar on scroll, so blocking and site time continue. Unit tests in `FrontAddressTest`. Phone (Full APK from this commit, installed with `install -r`): youtube.com at 0 min, Accessibility method; typing kept Chrome open, Enter sent it home in about 1 s, 5 reopens and 3 `m.youtube.com` links with a swipe were all blocked, example.com stayed open. The youtube.com 0-min limit added for the test stays until midnight (the user agreed). Not checked: a non-zero site limit counting time while the bar is hidden; browsers other than Chrome. Release 1.2.5.2 only when the user asks.

## Next (2026-11-24): start with #50

#50 (feedback from the app, 1.2.5.1): the Blocker page vibrates when opened and transitions are not smooth. Same area as #47 (Blocker tab and its Goals/Apps sub-tabs still had 20-50 ms frames on first open). Plan: add the temporary frame logger (see the #47 note), open Blocker and each sub-tab, find the cause, fix, remove the logger, release 1.2.5.2 only when the user asks. Also open: #12/#44 (Apify returns no rows for https://lnkd.in/p/dEG72umG; check the run log in the Apify console), #37, #39, #41 (blocking untested), #40 (user tests TikTok), #2, #6.

## Latest (2026-11-23, ~21:40 IST): v1.2.5.1 RELEASED on GitHub (LinkedIn short-link and sign-up-page fixes); earlier: v1.2.5.0 (Reddit archive)

**Fixed after 1.2.5.0 (#49, #12).** (1) `ShareUrls.kt`: `lnkd.in/p/<id>` was cut to `lnkd.in/p` (404). (2) `_resolveShort` in `runner.dart` resolves a lnkd.in link once (301 Location, no cookies). (3) `parseLinkedIn` now rejects LinkedIn's sign-up page (`Sign Up | LinkedIn`, '500 million+ members'), which had been saved as a wrong note. (4) Apify gets `feed/update/urn:li:activity:<id>` (`linkedInApifyUrl`). (5) `apifyActorRun` throws with the HTTP status; a run that returns nothing says so. 180 Dart tests, Kotlin tests pass; Full APK with these fixes is on the phone.

**Still failing (#12, #44).** With a valid Apify key the actor `memo23~linkedin-posts-scraper` returns `[]` for `https://lnkd.in/p/dEG72umG` (post by himanii, share id 7529787441982099457), with the activity URL and with the /posts/ URL. Cause unknown without the actor's own run log (Apify console, run history). Open-source scrapers do the same thing (cookies, or a paid fetch service); faking a crawler user agent was not tried because it bypasses LinkedIn's login wall and the Terms forbid that. Options: try another public Apify LinkedIn actor, or use Read in app.

**Phone results this round.** X video tweet saved (#42 closed); Reddit saved through Arctic Shift (#43, #48 closed); 0 accepted in the Reels limit (#45, not saved). Not tested: #37, #39, #41 blocking, #40 (user will test).

## Latest (2026-11-23, ~20:30 IST): 1.2.5.0 built and installed (Full) on the phone; phone checks done for #42, #43/#48; rest listed below

**Done this round.** Reddit now reads from the Arctic Shift archive first (`redditPostId`, `arcticShiftPostUri`, `parseArcticShiftPost` in `reddit.dart`, `Runner._reddit`), Apify second; Privacy/Terms 2.5, `legal_v7`, ENDPOINTS section REDDIT-ARCTIC. Reels limit hint wraps (`helperMaxLines: 2`). Version 1.2.5.0 (build 58).

**Phone results (Full 1.2.5.0, adb only, nothing saved in your settings).** #42 X video tweet: saved, video downloaded. #43/#48 Reddit post from the archive: saved without a key. #12/#44 LinkedIn `lnkd.in` link: page and embed fail from a login wall, then Apify answers "key was rejected": **the Apify key in Settings is not accepted; re-enter it and test again.** #45: 0 accepted in the Daily limit field (not saved). #41: Scroll guard card shows and counted 7 swipes today. Not tested: #37 (needs a site limit and the VPN consent dialog, which only the user can accept), #39 Spotlight, #40 TikTok (not installed; user will test, noted on #40), Reddit via Apify (needs a `/s/` share link or a post under an hour old), #2 and #6 (user said skip).

## Latest (2026-11-23, ~20:10 IST): v1.2.4.0 RELEASED on GitHub (both APKs and SHA256SUMS, digests checked); #38 closed

Checks before release: analyze clean, 177 Dart tests, `check_apks.sh` OK. NOT phone-checked (the phone was in use, nothing tapped). Still open, each waits on something outside the code: #2 (your accounts), #6 (F-Droid, from ~2027-02-05), #12 (LinkedIn embed on the phone), #37 (site method on the phone), #39 (Spotlight id), #40 (TikTok not installed), #41 (scroll guard on the phone), #42 (X video tweet), #43/#44 (real Apify key), #45 (0 min on the phone). Next: phone checks, then close those that pass.

## Latest (2026-11-23, ~14:30 IST): #47 frame drops DONE and closed; everything pushed to `main` (15b8c0d); 1.2.4.0 NOT released

**#47 (closed).** Measured with a temporary frame logger (removed): the app was raster-bound (build 2-8 ms, raster 20-200 ms). Fixes: marble background drawn once into an image (`liquid.dart`), tabs switch at once with `Offstage`, page opening is a slide only, `Reveal` rises without a fade, `Skeleton` is static, `InkRipple` instead of `InkSparkle`, no blurred shadow on `Glass`. Worst frame in a tab tour went from about 266 ms to about 52 ms. Not at a steady 90 Hz: the Blocker tab and its Goals/Apps sub-tabs still show a few 20-50 ms frames on first open (mostly first-time text drawing). To measure again, add `SchedulerBinding.instance.addTimingsCallback` in `runReelBot` and log frames over 20 ms; remove it afterwards.

**Other work today.** "Your pattern" (habits) card removed from Blocker > Reels (`habits.dart` now holds only `ScrollRule`, `ScrollState`, `ScrollBridge`; the file name is misleading). Unused `ReelTracker.currentApp` removed. `mobile/CLAUDE.md` added. Checks: `flutter analyze` clean, 177 Dart tests pass, Kotlin Full and Semi unit tests pass.

**GitHub issues (each got a status comment on 2026-11-23):**

| # | State | What is left |
|---|-------|--------------|
| 47 | closed | nothing |
| 36 | closed earlier | nothing |
| 2 | open | waits on the user (own accounts for the goals) |
| 6 | open | F-Droid: submit again from about 2027-02-05 |
| 12 | open | LinkedIn embed route not tried on the phone |
| 37 | open | site method picker: real site limit on the phone |
| 38 | closed | done, released in 1.2.4.0 |
| 39 | open | Spotlight id not confirmed on screen |
| 40 | open | TikTok not installed on the phone |
| 41 | open | scroll guard tripping and going home not checked |
| 42 | open | an X video tweet not tried |
| 43, 44 | open | need a real Apify key |
| 45 | open | typing 0 min in the Reels tab on the phone |

**Next.** Do the phone checks above, then release 1.2.4.0: bump `AppServices.version` and `pubspec.yaml`, release notes (both `play/release-notes` files), `docs/RELEASES.md` row, build both APKs (the semi APK is stale), run `tool/check_apks.sh`, publish assets named `reel-analyser-<tag>-full.apk`, `-semi.apk`, `SHA256SUMS`. Ask the user before publishing. Settings "Loading your keys" and the Ask tab still have no skeleton. Do not run `dart format`; check test exit status, not `| tail`.

Hand-off for a new chat. The list of what is still to do is in [TODO.md](TODO.md). Read this first, then that.

## Latest (2026-11-23): 1.2.4.0 built (full APK only), installed on the phone, NOT released, NOT phone-checked

- #36 VPN no internet: `DnsVpnService` now follows the real network (callback), asks IPv4 and IPv6 DNS servers in turn with `bindSocket` + `protect`, public servers as last resort (`DnsUpstream`, tested). Cause not reproduced on the phone (needs a site limit set in the UI); fix is from reading the code: upstream was chosen once and IPv6-only mobile DNS was dropped.
- #37 sites: Limits screen picker VPN or Accessibility (`site_method` pref, `SiteMethod`). Accessibility reads only the browser address bar (`ReelCounterService.siteInFront`), scope widens only with that method and a site limit. Switching is allowed only when the new method already works.
- #38 typed paragraph timer 90 s to 30 s (50 words kept).
- #39 Snapchat Spotlight (`spotlight_container`) and #40 TikTok (whole app) are blocker items; ids from open-source Scrolless (GPL-3.0, facts only). TikTok is not installed on the phone; Spotlight id not yet confirmed on screen.
- #41 Scroll guard tab (swipes a day, burst pause) and habits suggestions (`habits.dart`, computed on the phone). Counts only in short-video feeds. Rule is in prefs (not in backup yet).
- Follow-up same day: Scroll guard moved into Reel limits (no Scroll tab) and changed to runs: swipes that keep coming (a run ends after a quiet gap), past the limit the app is closed with the Home action and a short note, then feeds stay closed for the pause (idea from open-source blockers, which track a session and then leave the content; own code). Blocker pages restyled (`page_card.dart`, icons, tabs that do not wrap). LinkedIn (#12): after a 404 on the post page the app asks LinkedIn's public embed page once (`linkedInEmbedUrl`, works logged out from a computer; not yet tried on the phone).
- #45 Reels limit accepts 0 min (blocked all day; Kotlin range 0..1440, message 'blocked all day'). #46 the typed 50-word paragraph is gone from the blocker, limits, goals and scroll guard: `hold_gate.dart` (`askHold`) asks for a 30 s press-and-hold with a bar filling the whole screen; `paragraph_gate.dart` deleted. The username-change reason (`handle_change_screen.dart`, `ParagraphGuard`) is kept. No block screen any more: `BlockActivity` deleted, `GoHome` sends the user home (Accessibility Home, else the Home intent with overlay permission) with a one-line toast. VPN site hits draw nothing and send nobody home (a look-up can come from a prefetch). First-run dialog now says nothing is sent to the developer (flag `legal_v6`); Privacy and Terms 2.4; README, NOTICE, SECURITY, INSTALL and the Play description updated. Frame rate complaint: not yet diagnosed (adb gfxinfo/SurfaceFlinger give no frames for Flutter's surface).
- X, Reddit, LinkedIn Apify (#42, #43, #44): X posts via X's own embed endpoint `cdn.syndication.twimg.com/tweet-result?id=<id>&token=a` (no login, no third party; text, photos, best mp4 by resolution; tombstone = clean failure; `x_post.dart`). Reddit has no logged-out route (`.json`/`.rss`/old.reddit give 403/429), so it is read only through the user's Apify key (`trudax~reddit-scraper-lite`, `reddit.dart`); without a key the share fails with a plain message. LinkedIn: after page and embed fail, with an Apify key one run of `memo23~linkedin-posts-scraper` (`parseLinkedInActor`). The Apify actor field names come from the actors' public docs; NOT tested with a real key (no key available), so those two parsers are unverified against live output. X syndication was checked live on a computer, not yet on the phone. Link recognition in `ShareUrls.kt` (x.com/twitter.com status, reddit comments, /s/ share links passed on unresolved, redd.it). Privacy/Terms 2.3 text extended. Not done: Reddit Read in app, PRAW/OAuth route.
- Legal: Privacy and Terms 2.3. To check on the phone: add a site limit, use VPN and Accessibility methods, internet works on Wi-Fi and mobile data; open Snapchat Spotlight with a block set; scroll guard pause.

Hand-off for a new chat. The list of what is still to do is in [TODO.md](TODO.md). Read this first, then that.

## Latest (2026-11-15): v1.2.3.1 RELEASED (legal texts, Accessibility payment-app warning, #35); before it v1.2.3.0 RELEASED (blocking via local DNS VPN + Usage access/overlay, no screen reading, #34); before it v1.2.2.6 RELEASED (erase also hides old Insights time); before it v1.2.2.5 RELEASED (narrow Accessibility scope, lock full-only, smoothness); before it v1.2.2.4 RELEASED (fixes fingerprint unlock, #29); before it v1.2.2.3 RELEASED (instant app lock, full-only fingerprint unlock, rename to Reel Analyser + Blocker); before it v1.2.2.1 RELEASED (adds the App lock, #26); before it v1.2.2.0 RELEASED (GitHub). Issues #15 to #25 closed; not all checked on the phone

- Issues #16 to #22 (all open until the phone check). Apps & sites: `lib/full/limits*.dart`, Kotlin `AppLimits.kt`, `ReelCounterService.enforceLimits` (second `BlockMeter`, keys `app:<pkg>` and `site:<host>` in `block_use`). Blocker history removed (Dart and Kotlin; old rows dropped on start). Parallel analysis: `_workerCount` in `runner.dart` now counts Gemini plus OpenAI and Claude keys (it was Gemini keys only, so one Gemini key meant one reel at a time).
- To check on the phone: add an app and a site with 1 minute, use them, see the block screen; bars move; Edit/Cancel; Save hidden until an edit; two reels shared together run at once.

## Latest (2026-11-12): v1.2.1.3 released; 1.2.1.4 ready, NOT released or committed (user said stop)

- **LinkedIn (#12): full details and what to check next are in [LINKEDIN.md](LINKEDIN.md).**
- 1.2.1.4 (uncommitted, not built or released): Gemini keys rotate per analysis and the place is saved at once (closes #15). Failed LinkedIn shares have Read in app (in-app page, no login; the loaded HTML is analysed instead of fetching). On the phone a public post gave LinkedIn "Page not found" even in the in-app page at 15:28 and loaded a minute later, so the 404 is intermittent per network; open-source scrapers either need a login (ban risk) or a paid fetch service (Scrapfly, Bright Data). #12 stays open.
- v1.2.1.3 (#12, still open): a share the background analysis could not finish now shows in a "Could not analyse N shares" card at the top of the Library (reason, Retry, Dismiss; last 7 days). Cause of the LinkedIn failures: LinkedIn sometimes answers the phone with HTTP 404 for a public post that loads fine from a computer, often when several posts are shared at once. The app never retries on its own and never logs in (no ban risk). Not fixed: the 404 itself.
- v1.2.1.2: the update check runs on every app open, survives the GitHub API rate limit, retries dropped downloads and offers the release page on failure.
- F-Droid closed !56876 and !56877 on 2026-11-12: the app is under 3 months old (Inclusion Policy). No code change needed; submit again from about 2027-02-05 (first commit 2026-11-05).
- v1.2.1.1: delete a chat from the Ask screen (closes #13). #12 (LinkedIn) is worked on in 1.2.1.3.
- v1.2.1.0: LinkedIn multi-part analysis, the Support and Refund Policy and updated legal texts, and F-Droid groundwork. The F-Droid recipes are in `fdroid/`, and [FDROID.md](FDROID.md) explains them. Both apps were submitted on 2026-11-11 as fdroiddata MRs !56876 (Full) and !56877 (Semi); they are waiting for review and for F-Droid to trigger CI.

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
