import 'app.dart';
import 'pipeline/background.dart';
import 'semi_features.dart';

/// Entry point of the semi build (`flutter build apk --flavor semi -t lib/main_semi.dart`). It imports nothing from `lib/full/`.
@pragma('vm:entry-point')
void semiBackgroundDispatcher() => runBackground(const SemiFeatures());

Future<void> main() => runReelBot(const SemiFeatures(), semiBackgroundDispatcher);
