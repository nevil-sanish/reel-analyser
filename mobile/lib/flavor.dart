/// True in the Google Play build (`--dart-define=PLAY_BUILD=true`, flavor `play`). Play policy rules out two things the
/// download build does: reading other apps' screens with an Accessibility service, and updating itself from a file.
/// So the Play build counts nothing from the screen (Usage access still gives time in the apps) and never offers an APK.
const bool kPlayBuild = bool.fromEnvironment('PLAY_BUILD');
