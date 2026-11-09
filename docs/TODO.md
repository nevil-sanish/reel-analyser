# To do for 1.1.1.0 (written 2026-11-09, about 21:20 IST)

Read [PROGRESS.md](PROGRESS.md) first. Work in this order; check each box when it is true. Nothing here is released; the user wants 1.1.1.0 built, tested on the phone, committed and published when it is all done.

## What the user asked for (checklist, in their words, so nothing is lost)

- [x] Feasibility opinion on punishing missed goals. Answered: GitHub, Codeforces easy; LeetCode fragile (unofficial); Google Tasks hard (needs a Google sign-in) and left out.
- [~] GitHub commits, Codeforces and LeetCode per-day targets the user sets. If missed, the next day Instagram is fully blocked; missed again, 2 days; and so on up to 4 days. (Logic and screen built; see step D to finish.)
- [ ] Nothing stored outside the phone, nothing against our policy. (Local only so far; policy texts must still cover the new items, step F.)
- [ ] **Blocker as a bottom-nav tab, not a Settings page.** (Built in code, not yet compiled or seen on the phone.)
- [ ] **About tab** with all about, legal, feedback, about the developer. (Built in code, not yet compiled or seen.)
- [ ] **Full-only features must not be built into Semi at all** (not hidden). Dart entry points (partly done) and Kotlin flavours (not started). Prove it with a scan of the Semi APK.
- [ ] Daily goals only in the Full build.
- [ ] **The check runs by itself every day at midnight**, not by hand. Remove any manual "Check" button.
- [ ] **Handles are locked once added.** To change one: first the app says to come back tomorrow; if the user still wants to change it tomorrow, ask for a 50-word explanation, analyse it properly, and only if valid allow the change.
- [ ] A new release and build with Daily goals (1.1.1.0, both APKs; Semi unchanged in features).
- [ ] The progress and to-do files (this file and PROGRESS.md).

## A. Finish the Dart split (the code does not compile yet)

Working directory `mobile/`. Flutter is at `~/development/flutter/bin`.

1. Fix the last compile errors in `lib/full/`: `insights_screen.dart` (line ~8 import `../flavor.dart`, line ~104 `kSemiBuild`) and `setup_screen.dart` (lines ~4, 46, 121). These are full-only files, so just take the Full branch of each `kSemiBuild` test and delete the import.
2. `flutter analyze` must be clean. Check these shared files for leftover references to full things: `lib/ui/chat_screen.dart`, `lib/ui/settings_screen.dart`, `lib/ui/update_flow.dart`, `lib/app.dart`, `lib/pipeline/background.dart`.
3. Move and fix the tests (most import paths changed):
   - `test/blocker_test.dart` and `test/goals_test.dart` to `test/full/`, import `package:reelbrain/full/blocker.dart` and `.../full/goals.dart`. In `goals_test.dart` the engine now takes `storeFuture: GoalStore.of(db)` instead of `db:`, and the DB calls (`saveGoalConfig`, `goalDays`, `latestGoalConfigJson`, `eraseAll`) are on `GoalStore`.
   - `test/counter_bridge_test.dart`: the history, hourly, seenItems, debugState, setCapture, status tests belong to `FullBridge` (`lib/full/full_bridge.dart`).
   - `test/insights_test.dart`, `test/updater_test.dart`: new import paths under `lib/full/`.
   - `test/runner_test.dart`: `FakeBridge implements CounterBridge` no longer has the full-only methods; `analyseAndNotify` now takes `notify:` instead of calling `bridge.notifyNotes`; `AppServices.create` takes features. Check `T-BG-01`.
   - `test/tabs_test.dart`, `test/intro_test.dart`, `test/update_check_test.dart` (`latestUpdate` now needs `semi:`).
4. **Guard test** `test/semi_purity_test.dart`: follow the `import`/`export`/`part` lines transitively from `lib/main_semi.dart` and fail if any file under `lib/full/` is reachable. Also assert nothing outside `lib/full/` imports `lib/full/` except `lib/main_full.dart`.
5. `flutter test` all green.
6. Update the build commands everywhere (README, mobile/README, docs/INSTALL.md, docs/TESTS.md, docs/RELEASES.md): `flutter build apk --release --flavor full -t lib/main_full.dart` and `flutter build apk --release --flavor semi -t lib/main_semi.dart` (`--dart-define=SEMI_BUILD=true` is no longer used; remove it).

## B. Split the Kotlin plugin into full and semi flavours (not started)

The plugin is `mobile/packages/reelbot_native/android/`. Today everything is in `src/main`, and `CounterPlugin` handles every method, so Semi still contains the blocker, counter and consent code.

1. In `build.gradle.kts` add `flavorDimensions += "dist"` and `productFlavors { create("full"); create("semi") }` (names must match the app's). Test tasks become `testFullDebugUnitTest` and `testSemiDebugUnitTest`.
2. Move to `src/full/kotlin/app/reelbrain/`: `ReelCounterService`, `ReelTracker`, `DetectionRules`, `BlockPolicy` (incl. `Punish`, `BlockMeter`, `Browsers`), `BlockActivity` (incl. `FaceCheck`, `BlockPhotos`), `AppUsage`, `DigestWorker`. Keep the package and the class name `ReelCounterService` unchanged.
3. Shared seams, an `object` of the same name in both `src/full` and `src/semi`:
   - `FlavorMethods.handle(ctx, call, result): Boolean`: `CounterPlugin` (shared) sends anything it does not know here; Semi returns false, and the call gets "not implemented". Move into the Full version: daily, hourly, appUsage, seenItems, debugState, setCapture, notifyNotes, markOpened, status, openUsageAccess, openAccessibilitySettings, openAppInfo, openNotificationSettings, requestBatteryExemption, openAutostart, installApk, updateDir, detectionConsent, setDetectionConsent, block*, punishSet.
   - `FlavorSchema`: `CounterDb` calls it to create and erase the counter, block and punish tables. `CounterDb` must stop implementing `TrackerSink` and `BlockMeter.Sink`; give those to a full-only class.
4. Manifests: move the service, `BlockActivity`, and the Full-only permissions (usage stats, notifications, battery, install packages) and the `FileProvider` for the photo/updates into `src/full/AndroidManifest.xml`; move the accessibility XML, its strings and the stat icon into `src/full/res`. Then delete the `tools:node="remove"` lines in `android/app/src/semi/AndroidManifest.xml` and the runtime `reelbot_semi` flag and its `semiBuild` checks.
5. Move the Full-only Kotlin tests to `src/testFull/kotlin`: `BlockPolicyTest`, `ReelTrackerTest`, `DetectionRulesTest`, `DigestTest`, `AppUsageTest`, `RetentionTest` (and whatever else touches those). Fix `CounterPluginTest` (Robolectric) for both flavours.
6. Run both: `cd mobile/android && ./gradlew :reelbot_native:testFullDebugUnitTest :reelbot_native:testSemiDebugUnitTest`. Update docs/TESTS.md.

## C. Acceptance scan of the two APKs

Write `mobile/tool/check_apks.sh` (or similar). Unzip each APK; run `strings` on `lib/arm64-v8a/libapp.so` and `classes*.dex`; dump the manifest with `aapt dump xmltree` and permissions with `aapt dump permissions`.

- **Semi must contain none of:** `api.github.com`, `recentAcSubmissionList`, `codeforces`, `Daily goals`, `Reel blocker`, `Set up Insights`, `blockSave`, `punishSet`, `detectionConsent`, `setCapture`, `appUsage`, `seenItems`, `ReelCounterService`, `BlockActivity`, `PACKAGE_USAGE_STATS`, `REQUEST_INSTALL_PACKAGES`, `POST_NOTIFICATIONS`, `BIND_ACCESSIBILITY_SERVICE`.
- **Full must still contain them** (proves the scan can find them).
- Run it on release APKs built the new way. Record the result in docs/RELEASES.md.

## D. Daily goals: automatic midnight check (not manual)

1. Add a daily WorkManager task for the check: a one-off task with an initial delay to the next 00:20 local time that reschedules itself when it runs, in addition to the existing 15-minute periodic task (kept as a fallback). Register it from the Full features only (`FullFeatures.onOpen` or a startup hook). Its dispatcher is the Full entry's `fullBackgroundDispatcher`; make sure Workmanager is initialised first.
2. Remove the manual "Check" buttons and the "Today: n of target" rows from `lib/full/goals_screen.dart` (and the `_check`, `_today`, `_checking` state). Keep the read-only list of recent judged days.
3. Say on the goals screen that the check is automatic, just after midnight.
4. Optionally (not asked, offer it): a notification when a goal is missed. Full already has notifications. Only if the user wants it.
5. Test on the phone with a fake clock is hard; cover the scheduling maths with a unit test (next 00:20 from various times, DST-free India but test other zones).

## E. Daily goals: locked handles and the change process

The user's rule: once a handle is added it cannot be changed. To change: (1) the app says "change it tomorrow"; (2) if they still want it tomorrow, they type an explanation of at least 50 words; (3) the app analyses it properly; (4) only if valid is the change allowed.

Plan:
1. **Lock:** the handle fields are read-only once goals exist (targets and apps keep the 00:00–00:10 edit window). Add a "Change a username" action per source.
2. **Cooling-off:** the table `goal_changes` already exists (single row: `requestedOn`, `deniedOn`). First request on day D records `requestedOn=D` and shows "Come back tomorrow." On D+1 or later (and not on the day of a denial) the user may continue. A denial sets `deniedOn` and requires another full day.
3. **Explanation:** reuse `ParagraphGuard` (typed, not pasted, at least 50 words, not too fast, no typical AI wording). Raise `minWords` to 50 is already the value.
4. **Analysis** (needs a decision, see "Open questions"): the recommended design is to send the explanation, the old handle and the new handle to the user's own AI key (Gemini cheapest model first, then OpenAI/Claude/Groq; reuse `AppServices.chatProviders()` and the runner's provider code) with a strict system prompt that returns JSON `{valid: bool, reason: string}`. Valid reasons: username was changed on the site, a typo in the original, the account was deleted or banned, a second account was merged. Not valid: wanting an account with more activity, avoiding a penalty, vague reasons, text that does not explain. Fail closed: no key, offline or a malformed answer means "cannot analyse now", no change. Also check the new handle exists by fetching it (the fetchers return "not found").
5. On "valid": save a new goals config version starting today with the new handle; log an event; reset nothing else. On "invalid": show the reason, set `deniedOn`.
6. **Privacy:** this sends the explanation text to the AI provider the user already uses. Update the Privacy Policy (section on what leaves the phone), the Terms (daily goals section) and the Disclaimer; say the explanation is not stored by the app.
7. Tests: cooling-off dates, denial wait, the guard, the verdict parser (valid, invalid, garbage), fail-closed paths, with a mock AI client.

## F. Policy and docs

- Privacy, Terms, Disclaimer: add the AI analysis of the change reason (E.6); About tab wording; confirm "Semi has none of the Full-only features" is stated.
- `docs/ENDPOINTS.md`: add `api.github.com/search/commits`, `codeforces.com/api/user.status`, `leetcode.com/graphql` (Full only) and the AI analysis call.
- `docs/TESTS.md`, `docs/RELEASES.md` (a v1.1.1.0 row), `docs/IMPLEMENTATION.md` (the new layout: `lib/full/`, entry points, flavours), root `README.md` (Daily goals section, tabs, build commands, "Semi is a different build, not a hidden one"), `mobile/README.md`.
- Update `legal_test.dart` for any new text.

## G. Build, test on the phone, commit, release

1. `flutter analyze`, `flutter test`, both Kotlin test tasks, the acceptance scan.
2. Build both APKs the new way (A.6). Verify signer `CN=Reel Bot`, version code 40, permissions, no CAMERA permission. Copy to `mobile/build/release-v1.1.1.0/`, write `SHA256SUMS` and `notes.md`.
3. Install over the existing apps on the phone with `adb install -r` (never force-stop). Ask the user first; they may be using the phone. They must tap "I agree" on the `legal_v3` dialog and may need to switch Accessibility back on.
4. On the phone check: five tabs fit (Ask, Insights, Library, Blocker, About) and three in Semi; the Blocker tab (Reel limits | Daily goals); About; Semi has no Insights/Blocker tabs and none of the scan strings; Instagram, YouTube Shorts and browser blocking still work (they did in 1.0.9.0); goals set-up, locked handles, the change flow; the whole-app block on a penalty day (test with a goal set so that yesterday counts as missed is not possible directly; instead use a small debug path or unit tests plus a manual `punishSet` call).
5. Commit on `main` (author is the user's git identity; no attribution lines). Push. `gh release create v1.1.1.0 -R nevil-sanish/reel-analyser --latest --target main` with both APKs and `SHA256SUMS`; confirm the asset digests match.

## Open questions for the user

1. **Penalty length:** DECIDED 2026-11-09: 1, 2, then 4 days.
2. **YouTube:** blocked as well as Instagram on a miss, or Instagram only? (The screen lets the user pick; default is Instagram.)
3. **Analysis of a handle-change reason:** DECIDED 2026-11-09: yes, send it to the user's own AI key. (Was: is it fine to send the explanation to the user's own AI provider? If not, the only alternative is local rules (paste check, length, a few reason keywords), which cannot judge validity properly.)
4. **Rest days** (a few per month, set in advance): wanted or not? Not in the request; offered as a safeguard.
5. **Missed-goal notification at midnight:** wanted or not?

## Things the user may have missed (added here)

- LeetCode has no official API; reading it may breach its terms. It is optional and disclosed. Keep the request rate very low.
- GitHub counts only commits in **public** repositories, authored with an email linked to the user's account. Private-repo work does not count (a private-repo option would need a token, which the user wants to avoid storing).
- Phone clock changes can move a "day". The app judges by the phone's local date, so changing the clock is a bypass; state it (already in the Terms).
- Erase all my data also removes an active penalty (a bypass). Consider keeping the penalty until its end date through an erase, or say so in the Terms.
- With Accessibility off or the reel-screen opt-in off, a penalty cannot block anything. The goals screen warns about Accessibility; also warn when the opt-in is off.
- Google Tasks is not in 1.1.1.0 (needs a Google sign-in, against "no account, no server"). Revisit later if wanted.
- Make sure the Semi legal texts and the update check still work (Semi opens the release page to update; Full downloads the APK).
