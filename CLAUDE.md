# Reel Analyser: notes for Claude

Read `docs/PROGRESS.md` (hand-off) and `docs/TODO.md` before starting. Releases and their checks are logged in `docs/RELEASES.md`.

## GitHub issues: every piece of work has one
Repository: `nevil-sanish/reel-analyser`.

1. **Before starting any work** (a fix, a feature, a release task), find its issue with `gh issue list`. If none exists, open one with `gh issue create` that says what is wrong or wanted.
2. **While working**, put the issue number in each commit message (`#12`). Write `closes #N` only in the commit that finishes it.
3. **When it is done and checked** (analyze, tests, phone), close it with a comment saying what changed, the release it is in, and what was not checked: `gh issue close N --reason completed --comment "..."`. If the commit already closed it, add the comment with `gh issue comment`.
4. **Never close** an issue that waits on the user (for example #2, the user tests the goals with their own accounts) or on someone else (for example #6, F-Droid). Leave a comment with the current state instead.
5. When the work is complete, commit and push it to `main` (the user wants this every time).
6. At the end, tell the user which issues were opened, closed, and left open, and why.

## Build and phone
- Toolchain: `export PATH=~/development/flutter/bin:~/development/jdk/bin:$PATH JAVA_HOME=~/development/jdk ANDROID_HOME=~/development/android-sdk`.
- From `mobile/`: `flutter analyze`, `flutter test`, `flutter build apk --release --flavor full -t lib/main_full.dart` (and `semi` with `lib/main_semi.dart`), then `bash tool/check_apks.sh <full.apk> <semi.apk>`.
- Phone: `~/development/android-sdk/platform-tools/adb -s 00163354U000052`. In zsh, write the serial out in each command; a `$D` variable holding `-s ...` is not split into words.
- If the user is using the phone, stop tapping on it.

## Releases
- Bump `AppServices.version` in `mobile/lib/app_services.dart` (four parts, for example 1.2.1.2) and the build number in `mobile/pubspec.yaml` (`1.2.1+46`). Update both `play/release-notes/en-US/default.txt` files, add a row to `docs/RELEASES.md`, and update `docs/PROGRESS.md`.
- Release asset names must stay `reel-analyser-<tag>-full.apk`, `reel-analyser-<tag>-semi.apk` and `SHA256SUMS`, because the in-app updater looks for these names.
- Don't change the F-Droid recipes in `fdroid/` for a GitHub-only release.
