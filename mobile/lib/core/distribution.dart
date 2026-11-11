/// True in the builds F-Droid makes from source (`--dart-define=FDROID=true`). F-Droid delivers their updates, so these
/// builds never ask GitHub for a newer release and never offer to install one themselves.
const fromFdroid = bool.fromEnvironment('FDROID');
