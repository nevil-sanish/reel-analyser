/// True in the private build (`--dart-define=PRIVATE_BUILD=true`, flavor `private`): no Insights, no Accessibility,
/// no Usage access, no notifications, no update check. It needs the internet to reach your AI and nothing else.
/// The full build (flavor `full`) has every feature.
const bool kPrivateBuild = bool.fromEnvironment('PRIVATE_BUILD');
