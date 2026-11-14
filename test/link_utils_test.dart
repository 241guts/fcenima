import 'package:cinemax_player_app/app/link_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts a link from a pasted message', () {
    expect(
      LinkUtils.extractUrl('watch this: https://a.com/v/master.m3u8?t=1, ok'),
      'https://a.com/v/master.m3u8?t=1',
    );
  });

  test('adds https to bare hosts and www links', () {
    expect(LinkUtils.extractUrl('www.site.com/a.mp4'), 'https://www.site.com/a.mp4');
    expect(LinkUtils.extractUrl('site.com/a.mp4'), 'https://site.com/a.mp4');
    expect(LinkUtils.extractUrl('hello world'), isNull);
  });

  test('keeps rtsp and content links', () {
    expect(LinkUtils.extractUrl('rtsp://10.0.0.5/live'), 'rtsp://10.0.0.5/live');
    expect(LinkUtils.extractUrl('content://media/1'), 'content://media/1');
  });

  test('detects the format from the link', () {
    expect(LinkUtils.detect('https://a.com/x/master.m3u8?token=1'), LinkFormat.hls);
    expect(LinkUtils.detect('https://a.com/x/manifest.mpd'), LinkFormat.dash);
    expect(LinkUtils.detect('https://a.com/x.ism/manifest'), LinkFormat.smooth);
    expect(LinkUtils.detect('https://a.com/x/movie.mkv'), LinkFormat.direct);
    expect(LinkUtils.detect('https://a.com/watch?id=5'), LinkFormat.auto);
    expect(LinkUtils.needsSniff('https://a.com/watch?id=5'), isTrue);
  });

  test('parses headers', () {
    final h = LinkUtils.parseHeaders('Referer: https://a.com\nbad line\nX-A:  b ');
    expect(h, <String, String>{'Referer': 'https://a.com', 'X-A': 'b'});
  });

  test('dropbox links become direct links', () {
    expect(
      LinkUtils.extractUrl('https://www.dropbox.com/s/abc/video.mp4?dl=0'),
      'https://www.dropbox.com/s/abc/video.mp4?raw=1',
    );
  });
}
