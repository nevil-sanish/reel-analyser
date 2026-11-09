import 'app.dart';
import 'full/full_features.dart';
import 'pipeline/background.dart';

/// Entry point of the full build (`flutter build apk --flavor full -t lib/main_full.dart`). The background task has its own entry
/// function, so the full build's background engine loads the full build's features.
@pragma('vm:entry-point')
void fullBackgroundDispatcher() => runBackground(const FullFeatures());

Future<void> main() => runReelBot(const FullFeatures(), fullBackgroundDispatcher);
