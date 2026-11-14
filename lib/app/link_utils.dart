import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// How the player should treat a link.
enum LinkFormat { auto, hls, dash, smooth, direct }

/// Helpers that turn whatever the user pasted into something the player can
/// open: URL extraction, header parsing, format detection and sniffing.
class LinkUtils {
  LinkUtils._();

  /// Browser-like User-Agent: many servers refuse unknown agents.
  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static final RegExp _schemeUrl = RegExp(
    r'''((?:https?|rtsps?|rtmps?|content|file)://[^\s<>"']+)''',
    caseSensitive: false,
  );
  static final RegExp _wwwUrl = RegExp(
    r'''(www\.[^\s<>"']+)''',
    caseSensitive: false,
  );
  static final RegExp _bareHost = RegExp(
    r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?(/\S*)?$',
    caseSensitive: false,
  );
  static final RegExp _hlsPattern = RegExp(r'\.m3u8(?:$|[/?#&])');
  static final RegExp _dashPattern = RegExp(r'\.mpd(?:$|[/?#&])');
  static final RegExp _smoothPattern = RegExp(r'\.isml?(?:$|[/?#&])');
  static final RegExp _directExtension = RegExp(
    r'\.(mp4|m4v|mkv|webm|mov|avi|flv|ts|m2ts|mts|3gp|mpg|mpeg|ogv|'
    r'mp3|m4a|aac|flac|ogg|oga|opus|wav|ac3|amr)$',
  );

  /// Finds the first playable link inside [input] (a pasted message, a share
  /// text, a bare "site.com/video.mp4"...). Returns null when there is none.
  static String? extractUrl(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    final m = _schemeUrl.firstMatch(text);
    if (m != null) return _clean(m.group(1)!);
    final w = _wwwUrl.firstMatch(text);
    if (w != null) return _clean('https://${w.group(1)!}');
    if (!text.contains(RegExp(r'\s')) && _bareHost.hasMatch(text)) {
      return _clean('https://$text');
    }
    return null;
  }

  static String _clean(String raw) {
    var url = raw.replaceAll('&amp;', '&');
    while (url.isNotEmpty && '.,;:!?)]}>\'"'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    final uri = Uri.tryParse(url);
    if (uri != null && uri.host.toLowerCase().endsWith('dropbox.com')) {
      final q = Map<String, String>.from(uri.queryParameters)
        ..remove('dl')
        ..['raw'] = '1';
      return uri.replace(queryParameters: q).toString();
    }
    return url;
  }

  /// Parses "Name: value" lines into a header map.
  static Map<String, String> parseHeaders(String text) {
    final out = <String, String>{};
    for (final line in text.split(RegExp(r'[\r\n]+'))) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final name = line.substring(0, i).trim();
      final value = line.substring(i + 1).trim();
      if (name.isEmpty || value.isEmpty) continue;
      out[name] = value;
    }
    return out;
  }

  static String headersToText(Map<String, String> headers) =>
      headers.entries.map((e) => '${e.key}: ${e.value}').join('\n');

  /// Guesses the format from the link alone.
  static LinkFormat detect(String url) {
    final lower = url.toLowerCase();
    if (lower.startsWith('rtsp://') || lower.startsWith('rtsps://')) {
      return LinkFormat.direct;
    }
    if (_hlsPattern.hasMatch(lower)) return LinkFormat.hls;
    if (_dashPattern.hasMatch(lower)) return LinkFormat.dash;
    if (_smoothPattern.hasMatch(lower)) return LinkFormat.smooth;
    final path = (Uri.tryParse(url)?.path ?? lower).toLowerCase();
    if (_directExtension.hasMatch(path)) return LinkFormat.direct;
    return LinkFormat.auto;
  }

  /// True when the link is HTTP(S) with no recognizable extension, so asking
  /// the server what it is can help.
  static bool needsSniff(String url) {
    final lower = url.toLowerCase();
    return (lower.startsWith('http://') || lower.startsWith('https://')) &&
        detect(url) == LinkFormat.auto;
  }

  /// MIME type handed to the player for adaptive formats (null = let the
  /// player detect the container by itself).
  static String? mimeFor(LinkFormat format) {
    switch (format) {
      case LinkFormat.hls:
        return 'application/x-mpegURL';
      case LinkFormat.dash:
        return 'application/dash+xml';
      case LinkFormat.smooth:
        return 'application/vnd.ms-sstr+xml';
      case LinkFormat.auto:
      case LinkFormat.direct:
        return null;
    }
  }

  /// Reads the first bytes of the link to tell HLS, DASH and Smooth Streaming
  /// apart when the URL has no useful extension. Never throws: any failure
  /// returns [LinkFormat.auto] and the player decides.
  static Future<LinkFormat> sniff(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? userAgent,
    Duration timeout = const Duration(seconds: 7),
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return LinkFormat.auto;
    final client = HttpClient()..connectionTimeout = timeout;
    if (userAgent != null) client.userAgent = userAgent;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      for (final e in headers.entries) {
        request.headers.set(e.key, e.value);
      }
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1023');
      final response = await request.close().timeout(timeout);

      final type = (response.headers.contentType?.mimeType ?? '').toLowerCase();
      final fromType = _fromContentType(type);
      if (fromType != LinkFormat.auto) return fromType;

      final bytes = <int>[];
      await for (final chunk in response.timeout(timeout)) {
        bytes.addAll(chunk);
        if (bytes.length >= 1024) break;
      }
      final head = latin1.decode(bytes, allowInvalid: true);
      if (head.contains('#EXTM3U')) return LinkFormat.hls;
      if (head.contains('<MPD')) return LinkFormat.dash;
      if (head.contains('<SmoothStreamingMedia')) return LinkFormat.smooth;
      if (type.startsWith('video/') || type.startsWith('audio/')) {
        return LinkFormat.direct;
      }
      return LinkFormat.auto;
    } catch (_) {
      return LinkFormat.auto;
    } finally {
      client.close(force: true);
    }
  }

  static LinkFormat _fromContentType(String type) {
    if (type.contains('mpegurl')) return LinkFormat.hls;
    if (type.contains('dash+xml')) return LinkFormat.dash;
    if (type.contains('ms-sstr')) return LinkFormat.smooth;
    return LinkFormat.auto;
  }

  /// A readable title for the player: the file name, or else the host.
  static String titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    if (uri.pathSegments.isNotEmpty) {
      var last = uri.pathSegments.last;
      try {
        last = Uri.decodeComponent(last);
      } catch (_) {
        // keep the raw segment
      }
      if (last.trim().isNotEmpty) return last;
    }
    return uri.host.isNotEmpty ? uri.host : url;
  }
}
