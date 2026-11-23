import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reelbrain/core/models.dart';
import 'package:reelbrain/pipeline/linkedin.dart';
import 'package:reelbrain/pipeline/reddit.dart';
import 'package:reelbrain/pipeline/x_post.dart';

// Made-up posts in the shape the real endpoints answer with.
void main() {
  group('X', () {
    test('post id and hosts', () {
      expect(xPostId(Uri.parse('https://x.com/i/status/1893456789012345678')), '1893456789012345678');
      expect(xPostId(Uri.parse('https://x.com/someone')), isNull);
      expect(isXHost('x.com'), isTrue);
      expect(isXHost('mobile.twitter.com'), isTrue);
      expect(isXHost('evilx.com'), isFalse);
      expect(isXMedia('https://video.twimg.com/a.mp4'), isTrue);
      expect(isXMedia('http://video.twimg.com/a.mp4'), isFalse);
      expect(isXMedia('https://twimg.com.evil.test/a.mp4'), isFalse);
    });

    test('text, photos and the best mp4', () {
      final p = parseXPost(jsonEncode({
        'text': 'A short thread about tea http://t.co/abc123',
        'user': {'name': 'Tea Fan', 'screen_name': 'teafan'},
        'photos': [
          {'url': 'https://pbs.twimg.com/media/one.jpg'},
          {'url': 'https://evil.test/two.jpg'},
        ],
        'video': {
          'poster': 'https://pbs.twimg.com/ext_tw_video_thumb/p.jpg',
          'variants': [
            {'type': 'application/x-mpegURL', 'src': 'https://video.twimg.com/x.m3u8'},
            {'type': 'video/mp4', 'src': 'https://video.twimg.com/vid/avc1/320x568/a.mp4'},
            {'type': 'video/mp4', 'src': 'https://video.twimg.com/vid/avc1/720x1280/b.mp4'},
            {'type': 'video/mp4', 'src': 'https://evil.test/vid/avc1/1080x1920/c.mp4'},
          ],
        },
      }));
      expect(p.author, 'Tea Fan (@teafan)');
      expect(p.text, 'A short thread about tea');
      expect(p.images, ['https://pbs.twimg.com/media/one.jpg']);
      expect(p.videoUrl, 'https://video.twimg.com/vid/avc1/720x1280/b.mp4');
      expect(p.thumbnail, contains('twimg.com'));
      expect(p.isEmpty, isFalse);
    });

    test('a tombstone and junk are clean failures', () {
      final t = parseXPost(jsonEncode({'__typename': 'TweetTombstone'}));
      expect(t.unavailable, isTrue);
      expect(t.isEmpty, isTrue);
      expect(parseXPost('not json').isEmpty, isTrue);
      expect(parseXPost('[]').isEmpty, isTrue);
      expect(parseXPost('{}').isEmpty, isTrue);
    });
  });

  group('Reddit', () {
    test('first post of the actor rows', () {
      final p = parseRedditItems(jsonEncode([
        {'dataType': 'comment', 'body': 'ignore me'},
        {
          'dataType': 'post',
          'username': 'someone',
          'parsedCommunityName': 'android',
          'title': 'My setup',
          'body': 'Details here',
          'imageUrls': ['https://i.redd.it/a.jpg', 'https://evil.test/b.jpg'],
          'videoUrls': ['https://v.redd.it/xyz/DASH_720.mp4'],
        },
      ]));
      expect(p.author, 'someone');
      expect(p.subreddit, 'android');
      expect(p.title, 'My setup');
      expect(p.images, ['https://i.redd.it/a.jpg']);
      expect(p.videoUrl, 'https://v.redd.it/xyz/DASH_720.mp4');
    });

    test('empty answers', () {
      expect(parseRedditItems('[]').isEmpty, isTrue);
      expect(parseRedditItems('nope').isEmpty, isTrue);
      expect(isRedditHost('www.reddit.com'), isTrue);
      expect(isRedditHost('reddit.com.evil.test'), isFalse);
    });

    test('the key never goes in the actor input', () {
      expect(jsonEncode(redditActorInput('https://www.reddit.com/r/a/comments/abcd/')), isNot(contains('Bearer')));
    });
  });

  group('LinkedIn actor rows', () {
    test('text, author and a picture or a video', () {
      final pic = parseLinkedInActor(jsonEncode([
        {'postText': 'Hello', 'author': {'name': 'Ann'}, 'mediaUrl': 'https://media.licdn.com/dms/image/x.jpg'},
      ]));
      expect(pic.author, 'Ann');
      expect(pic.images, hasLength(1));
      final vid = parseLinkedInActor(jsonEncode([
        {'postText': 'Hi', 'mediaUrl': 'https://dms.licdn.com/playlist/vid/v2/abc'},
      ]));
      expect(vid.videos, hasLength(1));
      expect(parseLinkedInActor(jsonEncode([{'mediaUrl': 'https://evil.test/a.jpg'}])).isEmpty, isTrue);
      expect(parseLinkedInActor('[]').isEmpty, isTrue);
    });
  });

  test('X and Reddit notes are recognised', () {
    expect(isReelLink('https://x.com/i/status/1893456789012345678'), isTrue);
    expect(isReelLink('https://www.reddit.com/r/a/comments/abcd/'), isTrue);
    expect(isReelLink('https://evil.test/x.com'), isFalse);
  });
}
