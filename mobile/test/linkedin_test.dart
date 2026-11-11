import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/pipeline/linkedin.dart';

// Shapes copied from public, logged-out LinkedIn post pages (2026-11), with made-up content.
const _textPost = '''<html><head>
<meta property="og:title" content="Big news | Test Club">
<meta property="og:image" content="https://media.licdn.com/dms/image/v2/X/feedshare-shrink_800/0/1?e=1&amp;v=beta">
<script type="application/ld+json">{"@context":"http://schema.org","@type":"SocialMediaPosting","headline":"Big news",
"articleBody":"Big news! Registrations for our hackathon are open. 36 hours, prizes, mentors.",
"author":{"name":"Test Club","image":{"url":"https://media.licdn.com/dms/image/v2/C/company-logo_100_100/0/1"},"@type":"Organization"},
"image":[{"url":"https://media.licdn.com/dms/image/v2/X/feedshare-shrink_800/0/1?e=1","@type":"ImageObject"},
{"url":"https://media.licdn.com/dms/image/v2/Y/feedshare-shrink_800/0/2","@type":"ImageObject"}]}</script>
</head></html>''';

const _videoPost = '''<html><head>
<meta property="og:title" content="Beetles work as teams | Jane Doe">
<meta property="og:image" content="https://static.licdn.com/aero-v1/sc/h/logo">
<script type="application/ld+json">{"@context":"http://schema.org","@type":"VideoObject","name":"Beetles work as teams… | Jane Doe",
"description":"Beetles work as teams to move big things. A paper this year explains how.",
"contentUrl":"https://dms.licdn.com/playlist/vid/v2/Z/mp4-640p-30fp-crf28/0/1?e=2&v=beta",
"thumbnailUrl":"https://media.licdn.com/dms/image/v2/Z/videocover-high/0/1"}</script>
</head></html>''';

void main() {
  test('a text and picture post: full text, author, post pictures (not the company logo)', () {
    final p = parseLinkedIn(_textPost);
    expect(p.text, startsWith('Big news! Registrations'));
    expect(p.author, 'Test Club');
    expect(p.images, hasLength(2));
    expect(p.images.any((u) => u.contains('company-logo')), isFalse);
    expect(p.videoUrl, isEmpty);
  });

  test('a video post: the mp4 on LinkedIn media, the description, the author from the title', () {
    final p = parseLinkedIn(_videoPost);
    expect(p.videoUrl, startsWith('https://dms.licdn.com/playlist/vid/'));
    expect(p.text, startsWith('Beetles work as teams to move'));
    expect(p.author, 'Jane Doe');
    expect(p.thumbnail, contains('videocover'));
    expect(p.images, isEmpty, reason: 'the generic LinkedIn logo is not a post picture');
  });

  test('a login wall or an unknown page gives nothing', () {
    expect(parseLinkedIn('<html><title>Sign in</title></html>').isEmpty, isTrue);
  });

  test('only LinkedIn hosts and LinkedIn media are used', () {
    expect(isLinkedInHost('www.linkedin.com'), isTrue);
    expect(isLinkedInHost('in.linkedin.com'), isTrue);
    expect(isLinkedInHost('lnkd.in'), isTrue);
    expect(isLinkedInHost('linkedin.com.evil.com'), isFalse);
    expect(isLinkedInMedia('https://media.licdn.com/x'), isTrue);
    expect(isLinkedInMedia('http://media.licdn.com/x'), isFalse);
    expect(isLinkedInMedia('https://evil.com/licdn.com'), isFalse);
    final injected = parseLinkedIn(_textPost.replaceAll('https://media.licdn.com/dms/image/v2/Y', 'https://evil.com/Y'));
    expect(injected.images, hasLength(1));
  });

  test('LinkedIn notes are their own kind and their links open in the app', () {
    const r = Reel(url: 'https://www.linkedin.com/posts/x-123', app: 'linkedin', title: 't', summary: '', savedAt: 0);
    expect(r.kind, 'linkedin');
    expect(isReelLink(r.url), isTrue);
  });
}
