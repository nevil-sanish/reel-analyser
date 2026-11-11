import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/ui/web_screen.dart';

void main() {
  test('the in-app page stays on Instagram, YouTube and their login pages, over https', () {
    for (final ok in ['https://www.instagram.com/reel/x/', 'https://m.facebook.com/login', 'https://consent.youtube.com/m', 'https://youtu.be/x', 'https://www.linkedin.com/posts/x', 'about:blank']) {
      expect(allowedPage(ok), isTrue, reason: ok);
    }
    for (final bad in ['http://www.instagram.com/', 'https://evil.com/', 'https://instagram.com.evil.com/', 'https://notinstagram.com/', 'https://linkedin.com.evil.com/', 'file:///etc/passwd', 'intent://x#Intent;end', 'javascript:alert(1)', '']) {
      expect(allowedPage(bad), isFalse, reason: bad);
    }
  });
}
