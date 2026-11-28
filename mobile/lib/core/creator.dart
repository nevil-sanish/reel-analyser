import 'models.dart';

/// Who posted a note, as the note screen shows it: the account and the platform, and the account's public profile page when
/// the saved author is a handle (null for a plain name, a photo or no author).
class Creator {
  final String name;
  final String platform;
  final String? profile;
  const Creator(this.name, this.platform, this.profile);

  static const _platforms = {
    'instagram': 'Instagram',
    'youtube': 'YouTube',
    'x': 'X',
    'reddit': 'Reddit',
    'linkedin': 'LinkedIn',
    'facebook': 'Facebook',
    'tiktok': 'TikTok',
    'snapchat': 'Snapchat',
  };

  static final _handle = RegExp(r'^[A-Za-z0-9._-]{1,40}$');

  static Creator? of(Reel r) {
    final a = r.author.trim();
    if (a.isEmpty || r.app == 'photo') return null;
    final platform = _platforms[r.app] ?? '';
    String? link(String Function(String) url, String h) => _handle.hasMatch(h) ? url(Uri.encodeComponent(h)) : null;
    switch (r.app) {
      case 'instagram':
        final h = a.startsWith('@') ? a.substring(1) : a;
        return Creator(_handle.hasMatch(h) ? '@$h' : a, platform, link((h) => 'https://www.instagram.com/$h/', h));
      case 'reddit':
        final h = a.startsWith('u/') ? a.substring(2) : a;
        return Creator('u/$h', platform, link((h) => 'https://www.reddit.com/user/$h/', h));
      case 'x':
        final h = RegExp(r'\(@([A-Za-z0-9_]{1,15})\)').firstMatch(a)?.group(1) ?? (a.startsWith('@') ? a.substring(1) : '');
        return Creator(a, platform, h.isEmpty ? null : 'https://x.com/$h');
      case 'youtube':
      case 'tiktok':
        final h = a.startsWith('@') ? a.substring(1) : a;
        final site = r.app == 'youtube' ? 'https://www.youtube.com/@' : 'https://www.tiktok.com/@';
        return Creator(_handle.hasMatch(h) ? '@$h' : a, platform, link((h) => '$site$h', h));
      default:
        return Creator(a, platform, null);
    }
  }
}
