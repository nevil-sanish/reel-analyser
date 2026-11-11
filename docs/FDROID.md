# F-Droid (issue #6)

Both builds are prepared for F-Droid as two apps: **Reel Analyser** (`app.reelbrain`, the Full build) and **Reel Analyser Semi** (`app.reelbrain.semi`). F-Droid builds them from this repository's source code, signs them with its own key and delivers their updates.

## What is in this repository for F-Droid

| What | Where |
|---|---|
| The build recipes to submit to fdroiddata | `fdroid/app.reelbrain.yml`, `fdroid/app.reelbrain.semi.yml` |
| Store listing per build (title, short and full description, release notes, 512 px icon) | `mobile/android/app/src/full/play/`, `mobile/android/app/src/semi/play/` (Triple-T layout) |
| The pinned Flutter version the recipes read | `mobile/.fvmrc` (keep it equal to the Flutter used for releases) |
| The F-Droid build switch | `--dart-define=FDROID=true` → `lib/core/distribution.dart` `fromFdroid` |

With `FDROID=true` the app never asks GitHub for a newer release, and About shows "Updates come from F-Droid" instead of "Check for updates". The update-check code is tree-shaken out of the APK, so it isn't even present. The Full recipe also deletes the `REQUEST_INSTALL_PACKAGES` permission before building, so the F-Droid Full build can't install APKs.

## How other Flutter apps do it (checked 2026-11-11)

- **Aves** (`deckers.thibault.aves.libre`): a separate `libre` flavour and entry point for F-Droid (`flutter build apk -t lib/main_libre.dart --flavor libre`), Flutter as a git submodule, and `prebuild` sed lines that strip what F-Droid doesn't allow. Our recipes follow the same pattern with `--flavor full|semi -t lib/main_<flavour>.dart`.
- **LocalSend** (`org.localsend.localsend_app`): `pub get --enforce-lockfile`, `PUB_CACHE` inside the source tree so F-Droid's scanner can see the Dart packages, and `scandelete` for the package cache. It also uses reproducible builds (`Binaries:` and `AllowedAPKSigningKeys:`), so F-Droid ships the developer's own signed APK. We don't do that yet (see "Signing").
- **F-Droid's Flutter template** (`templates/build-flutter.yml` in fdroiddata): the Flutter srclib checked out at a version read from a file in the repository, which is what `mobile/.fvmrc` is for.

## Problems found and how they are handled

1. **Both apps would show the Semi store text.** In a Flutter (raw) build F-Droid doesn't know the Gradle flavour, so it reads every `src/*/play` folder, and the last one (`semi`) overwrites the other (fdroidserver `update.py`, `copy_triple_t_store_metadata`). Fixed in the recipes: each one `rm`s the other flavour's `play` folder.
2. **Self-updating isn't allowed on F-Droid.** Fixed with the `FDROID` build flag, plus removing the install permission in the Full recipe.
3. **No signing key on F-Droid's server.** The Gradle release build has no debug-key fallback. Without `key.properties` it builds an unsigned APK at `build/app/outputs/flutter-apk/app-<flavour>-release.apk`, which F-Droid then signs. Checked with a clean clone and no key.
4. **The NDK.** Flutter 3.47.9 asks for NDK 28.2.13676358, so the recipes set `ndk: r28c`.
5. **YAML.** A `": "` inside a recipe command breaks YAML parsing; the `.fvmrc` sed pattern avoids it. Both recipes pass `fdroid rewritemeta`, and `fdroid lint` passes except for its category and anti-feature name lists, which need fdroiddata's own config to load. The names used are from fdroiddata's `config/categories.yml` and `config/antiFeatures.yml`.

## Checks run (2026-11-11, fdroidserver 2.4.5)

- **Clean clone build:** `flutter pub get --enforce-lockfile`, then both flavours built with `--dart-define=FDROID=true`.
  - Full has no install permission.
  - Semi asks only for internet, network state, wake lock, run at boot and a short foreground service.
- **`fdroid scanner` on the built Full APK:** no non-free classes, no extra signing blocks.
- **F-Droid's source scanner on the repository:** nothing found in the source. The only findings were local build caches (`.dart_tool`, `.gradle`), which don't exist on F-Droid's server because it scans before building.
- **Dependencies:** no Google Play Services, Firebase or other non-free libraries (Flutter, AndroidX, WorkManager, sqflite, webview_flutter, flutter_secure_storage, file_picker, http, cryptography).

## Anti-features

Both apps are labelled **NonFreeNet**: they need the user's own key for a proprietary AI service and read public Instagram, YouTube and LinkedIn pages. The optional Daily goals in the Full build also read GitHub, Codeforces and LeetCode. This label is expected and doesn't block inclusion.

The Full build uses an Accessibility service. F-Droid allows that, and the description explains what it reads.

## Signing

F-Droid signs its builds with its own key, so an F-Droid install and a GitHub install are different signatures. Android won't update one with the other: someone switching has to export their notes (Settings → Backup), uninstall, install the other one and import.

Later, reproducible builds (as LocalSend does) would let F-Droid ship the developer's own signed APK instead. That would need the GitHub release to be the same build as F-Droid's, which today it is not, because GitHub builds keep the in-app updater.

## Submitted (2026-11-11)

- Full: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/56876 (`metadata/app.reelbrain.yml`)
- Semi: https://gitlab.com/fdroid/fdroiddata/-/merge_requests/56877 (`metadata/app.reelbrain.semi.yml`)
- From the fork gitlab.com/nevilsanish/fdroiddata, branches `app.reelbrain` and `app.reelbrain.semi`. F-Droid signs with its own key (no reproducible build, by choice).
- GitLab won't run CI on the fork without identity verification (phone or card). As F-Droid's template says, that was skipped, and both MRs ask the F-Droid team to trigger CI. Watch the MRs for reviewer comments and CI results.

## Steps to submit (needs your own GitLab account)

1. Release the version the recipes point to (tag v1.2.1.0, `commit:` its full hash d7013c3…, versionCode 44) on GitHub. fdroiddata wants the full commit hash, not a tag.
2. Sign in at gitlab.com and fork https://gitlab.com/fdroid/fdroiddata.
3. In the fork, copy `fdroid/app.reelbrain.yml` and `fdroid/app.reelbrain.semi.yml` into `metadata/`, commit, and push to a new branch.
4. Optional but recommended: run `fdroid build -v -l app.reelbrain` in the fork (needs fdroidserver and an Android SDK), or let the merge request's CI pipeline build it.
5. Open one merge request per app (fdroiddata allows one app per MR), titled "New app: Reel Analyser" and "New app: Reel Analyser Semi". Fill in the template's checklist: MIT licence, the source link, the anti-features above, and that the Full build's self-updater is disabled in F-Droid builds.
6. Answer the reviewers' questions in the merge request. After it is merged, the apps appear on f-droid.org after the next build cycle, often a few days.

Screenshots are optional. If you want them, add clean ones (no personal notes, contacts or chats) as `mobile/android/app/src/<flavour>/play/listings/en-US/graphics/phone-screenshots/1.png`, `2.png` and so on.

## Each later release

Keep `mobile/.fvmrc` in step with the Flutter used, tag the release as `vX.Y.Z.W`, and bump the pubspec version code. F-Droid's checkupdates reads new tags and the version from `mobile/pubspec.yaml` and adds the build by itself (`AutoUpdateMode: Version`, `UpdateCheckMode: Tags`).
