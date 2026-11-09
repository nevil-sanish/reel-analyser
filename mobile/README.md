# Reel Analyser app

The Flutter app. Kotlin lives in `packages/reelbot_native`. See the root README and `docs/IMPLEMENTATION.md`.

- **Two builds:** `full` (every feature, including Insights and the Reel blocker) and `semi` (internet only). `lib/flavor.dart` and `android/app/src/semi/` define the difference.
- **Legal texts** (shown in the app, Settings → About and legal): `assets/legal/privacy.md`, `terms.md` and `disclaimer.md`. Plain Markdown with `#`, `##`, `-` and `**bold**` only, as `lib/ui/legal_screen.dart` renders just those. When one changes, bump the agreement flag in `lib/main.dart` (`legal_v2`) so everyone sees it again.
- **Tests:** `flutter test` here, and `cd android && ./gradlew :reelbot_native:testDebugUnitTest` for Kotlin.
