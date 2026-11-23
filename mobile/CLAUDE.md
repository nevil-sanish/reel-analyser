# Flutter app notes (mobile/)

The root `CLAUDE.md` rules apply (issues, releases, phone). Extra rules for this folder:

- Never run `dart format` here; it reformats most of `lib/`. Edit only the lines you mean to change.
- After `flutter test`, check the exit status. Piping to `tail` hides a failing run.
- Two flavors: `full` (blocker, limits, goals, Accessibility) and `semi`. Shared code is in `lib/`, full-only code in `lib/full/`, Kotlin full-only code in `packages/reelbot_native/android/src/full/`.
- Kotlin tests: from `android/`, `./gradlew :reelbot_native:testFullDebugUnitTest :reelbot_native:testSemiDebugUnitTest --offline -q`.
- No block screen exists. Blocking sends the user home (`GoHome`) with a toast. Confirming a change to a limit or goal is a 30 s press-and-hold (`lib/full/hold_gate.dart`), not typed text.
- Loading states use the skeletons in `lib/ui/skeletons.dart`, not spinners.
- Nothing about the user leaves the phone. Do not add analytics, crash reporting or any call to a developer server. Keep `assets/legal/*` and the first-run dialog true to that.
- Performance work: measure first (frame timings in logcat), never guess. Remove temporary loggers (`TEMP-PERF`) before committing.
- Read `docs/PROGRESS.md` before starting.
