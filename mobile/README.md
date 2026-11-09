# Reel Analyser app

The Flutter app. Kotlin lives in `packages/reelbot_native`. See the root README and `docs/IMPLEMENTATION.md`.

- **Two builds:** `full` (every feature, including Insights and the Reel blocker) and `semi` (internet only). They are separate builds, not a hidden switch: `lib/main_full.dart` and `lib/main_semi.dart` are the entry points, Full-only Dart is in `lib/full/`, and the Android plugin has `full` and `semi` flavours (`src/full` holds the counter, blocker and installer). `flutter build apk --release --flavor full -t lib/main_full.dart` (or `semi` with `lib/main_semi.dart`); `tool/check_apks.sh` proves Semi is clean.
- **Legal texts** (shown in the app, Settings → About and legal): `assets/legal/privacy.md`, `terms.md` and `disclaimer.md`. Plain Markdown with `#`, `##`, `-` and `**bold**` only, as `lib/ui/legal_screen.dart` renders just those. When one changes, bump the agreement flag in `lib/app.dart` (`legal_v3`) so everyone sees it again.
- **Tests:** `flutter test` here, and `cd android && ./gradlew :reelbot_native:testFullDebugUnitTest :reelbot_native:testSemiDebugUnitTest` for Kotlin.
