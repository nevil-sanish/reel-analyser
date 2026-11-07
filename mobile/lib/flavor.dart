/// True in the private build (`--dart-define=PRIVATE_BUILD=true`, flavor `private`). The two builds differ in only two
/// ways: the private one has no Insights (usage and reel counting) and none of the permissions Insights needs
/// (Accessibility, Usage access, battery exemption, notifications). Everything else is identical.
const bool kPrivateBuild = bool.fromEnvironment('PRIVATE_BUILD');
