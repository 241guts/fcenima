enum CinemaxTrackType { video, audio, text }

/// A selectable video quality, audio language or subtitle track.
class CinemaxTrack {
  const CinemaxTrack({
    required this.id,
    required this.type,
    this.language,
    this.label,
    this.width,
    this.height,
    this.bitrate,
    this.selected = false,
  });

  /// Opaque id understood by the native side ("group:track").
  final String id;
  final CinemaxTrackType type;
  final String? language;
  final String? label;
  final int? width;
  final int? height;
  final int? bitrate;
  final bool selected;

  String get displayName {
    if (type == CinemaxTrackType.video) {
      if (height != null) return '${height}p';
      if (bitrate != null) return '${(bitrate! / 1000).round()} kbps';
      return 'Video';
    }
    final l = label?.trim();
    if (l != null && l.isNotEmpty) return l;
    final name = _languageName(language);
    if (name != null) return name;
    return type == CinemaxTrackType.audio ? 'Audio' : 'Subtitles';
  }

  static int? _positive(Object? v) {
    final n = (v as num?)?.toInt();
    return (n == null || n <= 0) ? null : n;
  }

  static CinemaxTrack fromMap(Map<Object?, Object?> m) {
    final type = switch (m['type']) {
      'video' => CinemaxTrackType.video,
      'audio' => CinemaxTrackType.audio,
      _ => CinemaxTrackType.text,
    };
    final lang = m['language'] as String?;
    return CinemaxTrack(
      id: m['id'] as String,
      type: type,
      language: (lang == null || lang == 'und') ? null : lang,
      label: m['label'] as String?,
      width: _positive(m['width']),
      height: _positive(m['height']),
      bitrate: _positive(m['bitrate']),
      selected: m['selected'] == true,
    );
  }

  static const Map<String, String> _names = <String, String>{
    'ar': 'Arabic',
    'en': 'English',
    'fr': 'French',
    'es': 'Spanish',
    'de': 'German',
    'it': 'Italian',
    'pt': 'Portuguese',
    'tr': 'Turkish',
    'ru': 'Russian',
    'hi': 'Hindi',
    'ur': 'Urdu',
    'fa': 'Persian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'zh': 'Chinese',
  };

  static String? _languageName(String? code) {
    if (code == null || code.isEmpty) return null;
    final base = code.split(RegExp('[-_]')).first.toLowerCase();
    return _names[base] ?? base.toUpperCase();
  }
}
