/// An external subtitle file (WebVTT, SRT or SSA/ASS) attached to a source.
class CinemaxSubtitle {
  const CinemaxSubtitle({
    required this.url,
    this.language,
    this.label,
    this.mimeType,
  });

  final String url;

  /// BCP-47 language code such as `ar` or `en`.
  final String? language;
  final String? label;

  /// Optional MIME type. Guessed from the file extension when null.
  final String? mimeType;

  Map<String, Object?> toMap() => <String, Object?>{
        'url': url,
        'language': language,
        'label': label,
        'mimeType': mimeType,
      };
}

/// What to play. The host app builds this and hands it to the player.
class CinemaxMediaSource {
  const CinemaxMediaSource({
    required this.url,
    this.headers = const <String, String>{},
    this.mimeType,
    this.userAgent,
    this.subtitles = const <CinemaxSubtitle>[],
  });

  /// Direct media URL (progressive MP4/MKV, HLS .m3u8 or DASH .mpd).
  final String url;

  /// HTTP headers sent with every request (auth, referer, cookies...).
  final Map<String, String> headers;

  /// Optional MIME type, for URLs without a useful extension.
  /// Examples: `application/x-mpegURL`, `application/dash+xml`, `video/mp4`.
  final String? mimeType;

  final String? userAgent;
  final List<CinemaxSubtitle> subtitles;
}
