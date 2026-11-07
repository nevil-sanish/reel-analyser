/// True in the semi build (`--dart-define=SEMI_BUILD=true`, flavor `semi`). The two builds differ in only two
/// ways: the semi one has no Insights (usage and reel counting) and none of the permissions Insights needs
/// (Accessibility, Usage access, battery exemption, notifications). Everything else is identical.
const bool kSemiBuild = bool.fromEnvironment('SEMI_BUILD');
