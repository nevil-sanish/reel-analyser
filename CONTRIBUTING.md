# Contributing

Thank you for helping. Bugs and ideas go in [GitHub issues](https://github.com/nevil-sanish/reel-analyser/issues); pull requests are welcome.

## Licence of contributions

Reel Analyser is under the [MIT License](LICENSE). By sending a pull request you agree that your contribution is released under the same licence, and you confirm that you wrote it or have the right to submit it under that licence.

## Before you open a pull request

- Read [docs/RELEASES.md](docs/RELEASES.md): how commits, docs and tests stay in step.
- Keep the two builds apart: anything that needs a special Android permission belongs to the Full build only (`mobile/lib/full/` and the plugin's `full` flavour). The Semi build asks for nothing but the internet.
- No accounts, analytics, ads or trackers, and no non-free libraries (the app is built on F-Droid from source).
- Never commit API keys, `.env` files, keystores or fixtures that contain cookies or tokens.
- Run, in `mobile/`: `flutter analyze`, `flutter test`, and in `mobile/android/`: `./gradlew :reelbot_native:testFullDebugUnitTest :reelbot_native:testSemiDebugUnitTest`.

## Legal texts

If a change alters what data the app handles, which services it talks to, or what a feature does, update the texts in `mobile/assets/legal/` in the same pull request.

## Security

Report security problems privately, as described in [SECURITY.md](SECURITY.md).
